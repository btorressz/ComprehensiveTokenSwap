// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ComprehensiveTokenSwap
 * @dev This contract integrates multiple token swap functionalities including simple swaps, a DEX with AMM, multi-token swaps, limit orders, and flash swaps.
 */
contract ComprehensiveTokenSwap is ReentrancyGuard, Ownable {
    using Address for address;

    // Struct for the liquidity pool
    struct LiquidityPool {
        uint256 tokenAReserve;
        uint256 tokenBReserve;
    }

    // Struct for limit orders
    struct Order {
        address user;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 targetPrice;
        uint256 expiration;
        bool partialFill;
    }

    // Token addresses
    IERC20 public tokenA;
    IERC20 public tokenB;
    LiquidityPool public pool;

    // Array of supported tokens for multi-token swaps
    address[] public tokens;

    // Array of limit orders
    Order[] public orders;

    // Governance timelock
    TimelockController public timelock;

    // Price oracle
    AggregatorV3Interface internal priceFeed;

    // Fee rate (e.g., 0.3%)
    uint256 public feeRate = 3; // 0.3%
    address public feeRecipient;

    // Pause functionality
    bool public paused = false;

    // Events for various activities
    event SimpleSwap(address indexed user, uint256 amountA, uint256 amountB, uint256 fee);
    event AddLiquidity(address indexed user, uint256 amountA, uint256 amountB);
    event SwapAForB(address indexed user, uint256 amountA, uint256 amountB, uint256 fee);
    event PlaceOrder(address indexed user, address tokenASell, address tokenBBuy, uint256 amountA, uint256 targetPrice, uint256 expiration, bool partialFill);
    event ExecuteOrder(address indexed user, address tokenASell, address tokenBBuy, uint256 amountA, uint256 amountB);
    event CancelOrder(address indexed user, uint256 orderId);
    event FlashSwap(address indexed user, uint256 amountA, address target);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event Paused();
    event Unpaused();

    /**
     * @dev Initializes the contract with token addresses, supported tokens, and governance parameters.
     * @param _tokenA Address of the first ERC20 token.
     * @param _tokenB Address of the second ERC20 token.
     * @param _tokens Array of supported token addresses.
     * @param _timelock Address of the timelock controller for governance.
     * @param _priceFeed Address of the Chainlink price feed.
     * @param _initialOwner Address of the initial owner.
     */
    constructor(
        address _tokenA, 
        address _tokenB, 
        address[] memory _tokens, 
        address payable _timelock, 
        address _priceFeed, 
        address _initialOwner
    ) Ownable(_initialOwner) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        tokens = _tokens;
        timelock = TimelockController(_timelock);
        priceFeed = AggregatorV3Interface(_priceFeed);
        feeRecipient = _initialOwner;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * @dev Calculates the fee for a given amount.
     * @param amount The amount to calculate the fee for.
     * @return The fee amount.
     */
    function calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * feeRate) / 1000;
    }

    /**
     * @notice Simple swap function with slippage protection.
     * @param amount The amount of tokenA to swap for tokenB.
     * @param minAmountB The minimum amount of tokenB to receive.
     */
    function simpleSwap(uint256 amount, uint256 minAmountB) external whenNotPaused {
        uint256 exchangeRate = 1; // Simplified exchange rate
        uint256 amountB = amount * exchangeRate;
        uint256 fee = calculateFee(amountB);

        require(amountB >= minAmountB, "Slippage exceeded");

        require(tokenA.transferFrom(msg.sender, address(this), amount), "Token A transfer failed");
        require(tokenB.transfer(msg.sender, amountB - fee), "Token B transfer failed");
        require(tokenB.transfer(feeRecipient, fee), "Fee transfer failed");

        emit SimpleSwap(msg.sender, amount, amountB, fee);
    }

    /**
     * @notice Adds liquidity to the pool.
     * @param amountA Amount of tokenA to add.
     * @param amountB Amount of tokenB to add.
     */
    function addLiquidity(uint256 amountA, uint256 amountB) external whenNotPaused {
        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Token A transfer failed");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "Token B transfer failed");

        pool.tokenAReserve += amountA;
        pool.tokenBReserve += amountB;

        emit AddLiquidity(msg.sender, amountA, amountB);
    }

    /**
     * @notice Swaps a specified amount of tokenA for tokenB with slippage protection.
     * @param amountA The amount of tokenA to swap.
     * @param minAmountB The minimum amount of tokenB to receive.
     */
    function swapAForB(uint256 amountA, uint256 minAmountB) external whenNotPaused {
        uint256 amountB = getSwapAmount(amountA, pool.tokenAReserve, pool.tokenBReserve);
        uint256 fee = calculateFee(amountB);

        require(amountB >= minAmountB, "Slippage exceeded");

        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Token A transfer failed");
        require(tokenB.transfer(msg.sender, amountB - fee), "Token B transfer failed");
        require(tokenB.transfer(feeRecipient, fee), "Fee transfer failed");

        pool.tokenAReserve += amountA;
        pool.tokenBReserve -= amountB;

        emit SwapAForB(msg.sender, amountA, amountB, fee);
    }

    /**
     * @dev Calculates the swap amount based on the AMM formula.
     * @param amountIn The amount of input token.
     * @param reserveIn The reserve of input token in the pool.
     * @param reserveOut The reserve of output token in the pool.
     * @return The amount of output token to be received.
     */
    function getSwapAmount(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    /**
     * @notice Swaps a specified amount of a source token for a destination token.
     * @param srcToken The address of the source token.
     * @param dstToken The address of the destination token.
     * @param amount The amount of the source token to swap.
     * @param minDstAmount The minimum amount of destination token to receive.
     */
    function multiTokenSwap(address srcToken, address dstToken, uint256 amount, uint256 minDstAmount) external whenNotPaused {
        require(isTokenSupported(srcToken), "Source token not supported");
        require(isTokenSupported(dstToken), "Destination token not supported");

        IERC20(srcToken).transferFrom(msg.sender, address(this), amount);
        uint256 dstAmount = routeSwap(amount);
        uint256 fee = calculateFee(dstAmount);

        require(dstAmount >= minDstAmount, "Slippage exceeded");

        IERC20(dstToken).transfer(msg.sender, dstAmount - fee);
        IERC20(dstToken).transfer(feeRecipient, fee);
    }

    /**
     * @dev Routes the swap through intermediary tokens if necessary.
     * @param amount The amount of the source token.
     * @return The amount of the destination token to be received.
     */
    function routeSwap(uint256 amount) internal view returns (uint256) {
        // Simplified example: Assume a direct swap for demonstration
        uint256 exchangeRate = getExchangeRate();
        return amount * exchangeRate / 1e18;
    }

    /**
     * @dev Checks if a token is supported.
     * @param token The address of the token to check.
     * @return True if the token is supported, false otherwise.
     */
    function isTokenSupported(address token) internal view returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Gets the exchange rate between two tokens using Chainlink price feeds.
     * @return The exchange rate.
     */
    function getExchangeRate() internal view returns (uint256) {
        (,int price,,,) = priceFeed.latestRoundData();
        // Simplified example: Return the price as the exchange rate
        return uint256(price);
    }

    /**
     * @notice Places a limit order for a token swap.
     * @param tokenASell The address of the token to sell.
     * @param tokenBBuy The address of the token to buy.
     * @param amountA The amount of tokenA to sell.
     * @param targetPrice The target price for the swap (amountB per amountA).
     * @param expiration The expiration time of the order.
     * @param partialFill Whether the order can be partially filled.
     */
    function placeOrder(address tokenASell, address tokenBBuy, uint256 amountA, uint256 targetPrice, uint256 expiration, bool partialFill) external whenNotPaused {
        orders.push(Order({
            user: msg.sender,
            tokenA: tokenASell,
            tokenB: tokenBBuy,
            amountA: amountA,
            targetPrice: targetPrice,
            expiration: expiration,
            partialFill: partialFill
        }));

        emit PlaceOrder(msg.sender, tokenASell, tokenBBuy, amountA, targetPrice, expiration, partialFill);
    }

    /**
     * @notice Executes orders that meet the target price.
     * @param tokenASell The address of the token to sell.
     * @param tokenBBuy The address of the token to buy.
     * @param currentPrice The current price of tokenB per tokenA.
     */
    function executeOrders(address tokenASell, address tokenBBuy, uint256 currentPrice) external whenNotPaused {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].tokenA == tokenASell && orders[i].tokenB == tokenBBuy && orders[i].targetPrice <= currentPrice && orders[i].expiration >= block.timestamp) {
                uint256 amountB = orders[i].amountA * currentPrice / 1e18;
                if (orders[i].partialFill) {
                    // Partial fill logic
                    uint256 availableAmount = IERC20(tokenBBuy).balanceOf(address(this));
                    amountB = availableAmount < amountB ? availableAmount : amountB;
                }
                uint256 fee = calculateFee(amountB);
                IERC20(tokenASell).transferFrom(orders[i].user, msg.sender, orders[i].amountA);
                IERC20(tokenBBuy).transfer(orders[i].user, amountB - fee);
                IERC20(tokenBBuy).transfer(feeRecipient, fee);

                emit ExecuteOrder(orders[i].user, tokenASell, tokenBBuy, orders[i].amountA, amountB);

                delete orders[i];
            }
        }
    }

    /**
     * @notice Cancels a limit order.
     * @param orderId The ID of the order to cancel.
     */
    function cancelOrder(uint256 orderId) external {
        require(orders[orderId].user == msg.sender, "Not your order");
        delete orders[orderId];

        emit CancelOrder(msg.sender, orderId);
    }

    /**
     * @notice Executes a flash swap.
     * @param amountA The amount of tokenA to borrow.
     * @param target Address of the contract to call with the borrowed tokens.
     * @param data The call data to pass to the target contract.
     */
    function flashSwap(uint256 amountA, address target, bytes calldata data) external whenNotPaused nonReentrant {
        uint256 initialBalance = tokenA.balanceOf(address(this));
        require(tokenA.transfer(target, amountA), "Token A transfer failed");

        (bool success, ) = target.call(data);
        require(success, "External call failed");

        require(tokenA.balanceOf(address(this)) >= initialBalance, "Flash swap failed to repay");

        emit FlashSwap(msg.sender, amountA, target);
    }

    /**
     * @notice Pauses the contract.
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    /**
     * @notice Sets a new fee recipient.
     * @param newRecipient The address of the new fee recipient.
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        emit FeeRecipientChanged(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    /**
     * @notice Sets a new fee rate.
     * @param newFeeRate The new fee rate (in basis points).
     */
    function setFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 100, "Fee rate too high"); // Max 10%
        feeRate = newFeeRate;
    }
}

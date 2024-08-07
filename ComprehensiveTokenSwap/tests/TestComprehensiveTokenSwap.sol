// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "contracts/ComprehensiveTokenSwap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestComprehensiveTokenSwap
 * @dev This contract is used to test the ComprehensiveTokenSwap contract functionalities.
 */
contract TestComprehensiveTokenSwap {
    ComprehensiveTokenSwap public swapContract;
    TestToken public tokenA;
    TestToken public tokenB;
    address public owner;
    address[] public tokenArray;

    constructor() {
        owner = msg.sender;

        // Deploy test tokens
        tokenA = new TestToken("Token A", "TKNA", 1000000 * 10 ** 18);
        tokenB = new TestToken("Token B", "TKNB", 1000000 * 10 ** 18);

        // Initialize the array with addresses of tokenA and tokenB
        tokenArray.push(address(tokenA));
        tokenArray.push(address(tokenB));

        // Initialize the swap contract
        swapContract = new ComprehensiveTokenSwap(address(tokenA), address(tokenB), tokenArray, payable(address(this)), address(this), owner);

        // Distribute tokens to the owner for testing purposes
        tokenA.transfer(owner, 10000 * 10 ** 18);
        tokenB.transfer(owner, 10000 * 10 ** 18);
    }

    /**
     * @dev Adds liquidity to the swap contract.
     * @param amountA The amount of tokenA to add.
     * @param amountB The amount of tokenB to add.
     */
    function testAddLiquidity(uint256 amountA, uint256 amountB) external {
        require(msg.sender == owner, "Only owner can add liquidity");

        // Approve the swap contract to spend the tokens
        tokenA.approve(address(swapContract), amountA);
        tokenB.approve(address(swapContract), amountB);

        // Add liquidity to the pool
        swapContract.addLiquidity(amountA, amountB);
    }

    /**
     * @dev Tests the simple swap functionality.
     * @param amount The amount of tokenA to swap for tokenB.
     * @param minAmountB The minimum amount of tokenB to receive.
     */
    function testSimpleSwap(uint256 amount, uint256 minAmountB) external {
        require(msg.sender == owner, "Only owner can test simple swap");

        // Approve the swap contract to spend the tokens
        tokenA.approve(address(swapContract), amount);

        // Perform the simple swap
        swapContract.simpleSwap(amount, minAmountB);
    }

    /**
     * @dev Tests the multi-token swap functionality.
     * @param amount The amount of tokenA to swap for tokenB.
     * @param minDstAmount The minimum amount of destination token to receive.
     */
    function testMultiTokenSwap(uint256 amount, uint256 minDstAmount) external {
        require(msg.sender == owner, "Only owner can test multi-token swap");

        // Approve the swap contract to spend the tokens
        tokenA.approve(address(swapContract), amount);

        // Perform the multi-token swap
        swapContract.multiTokenSwap(address(tokenA), address(tokenB), amount, minDstAmount);
    }

    /**
     * @dev Places a limit order.
     * @param amountA The amount of tokenA to sell.
     * @param targetPrice The target price for the swap (amountB per amountA).
     * @param expiration The expiration time of the order.
     * @param partialFill Whether the order can be partially filled.
     */
    function testPlaceOrder(uint256 amountA, uint256 targetPrice, uint256 expiration, bool partialFill) external {
        require(msg.sender == owner, "Only owner can place order");

        // Approve the swap contract to spend the tokens
        tokenA.approve(address(swapContract), amountA);

        // Place the limit order
        swapContract.placeOrder(address(tokenA), address(tokenB), amountA, targetPrice, expiration, partialFill);
    }

    /**
     * @dev Executes orders that meet the target price.
     * @param currentPrice The current price of tokenB per tokenA.
     */
    function testExecuteOrders(uint256 currentPrice) external {
        require(msg.sender == owner, "Only owner can execute orders");

        // Execute orders that meet the current price
        swapContract.executeOrders(address(tokenA), address(tokenB), currentPrice);
    }

    /**
     * @dev Cancels a limit order.
     * @param orderId The ID of the order to cancel.
     */
    function testCancelOrder(uint256 orderId) external {
        require(msg.sender == owner, "Only owner can cancel order");

        // Cancel the limit order
        swapContract.cancelOrder(orderId);
    }

    /**
     * @dev Tests the flash swap functionality.
     * @param amountA The amount of tokenA to borrow.
     * @param target The address of the contract to call with the borrowed tokens.
     * @param data The call data to pass to the target contract.
     */
    function testFlashSwap(uint256 amountA, address target, bytes calldata data) external {
        require(msg.sender == owner, "Only owner can test flash swap");

        // Perform the flash swap
        swapContract.flashSwap(amountA, target, data);
    }
}

/**
 * @title TestToken
 * @dev A simple ERC20 token for testing purposes.
 */
contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

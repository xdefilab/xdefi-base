pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "./interface/IXPool.sol";
import "./interface/IXFactory.sol";
import "./interface/IXConfig.sol";
import "./interface/IERC20.sol";
import "./lib/XNum.sol";
import "./lib/SafeERC20.sol";
import "./lib/ReentrancyGuard.sol";

// WETH9
interface IWETH {
    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address, uint256) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

contract XSwapProxyV1 is ReentrancyGuard {
    using XNum for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX = 2**256 - 1;
    uint256 public constant BONE = 10**18;
    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    uint256 public constant MIN_BATCH_SWAPS = 1;
    uint256 public constant MAX_BATCH_SWAPS = 4;

    /**
     * the address used within the protocol to identify ETH
     */
    address public constant ETH_ADDR =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // WETH9
    IWETH weth;

    IXConfig public xconfig;

    constructor(address _weth, address _xconfig) public {
        weth = IWETH(_weth);
        xconfig = IXConfig(_xconfig);
    }

    function() external payable {}

    // Batch Swap
    struct Swap {
        address pool;
        uint256 tokenInParam; // tokenInAmount / maxAmountIn
        uint256 tokenOutParam; // minAmountOut / tokenAmountOut
        uint256 maxPrice;
    }

    function batchSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut
    ) public payable returns (uint256 totalAmountOut) {
        return
            batchSwapExactInRefer(
                swaps,
                tokenIn,
                tokenOut,
                totalAmountIn,
                minTotalAmountOut,
                address(0x0)
            );
    }

    function batchSwapExactInRefer(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut,
        address referrer
    ) public payable nonReentrant returns (uint256 totalAmountOut) {
        require(
            swaps.length >= MIN_BATCH_SWAPS && swaps.length <= MAX_BATCH_SWAPS,
            "ERR_BATCH_COUNT"
        );

        IERC20 TI = IERC20(tokenIn);
        if (transferFromAllTo(TI, totalAmountIn, address(this))) {
            TI = IERC20(address(weth));
        }

        IERC20 TO = IERC20(tokenOut);
        if (tokenOut == ETH_ADDR) {
            TO = IERC20(address(weth));
        }
        require(TI != TO, "ERR_SAME_TOKEN");

        uint256 actualTotalIn = 0;
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            IXPool pool = IXPool(swap.pool);

            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.safeApprove(swap.pool, 0);
                TI.safeApprove(swap.pool, MAX);
            }

            (uint256 tokenAmountOut, ) =
                pool.swapExactAmountInRefer(
                    address(TI),
                    swap.tokenInParam,
                    address(TO),
                    swap.tokenOutParam,
                    swap.maxPrice,
                    referrer
                );

            actualTotalIn = actualTotalIn.badd(swap.tokenInParam);
            totalAmountOut = tokenAmountOut.badd(totalAmountOut);
        }
        require(actualTotalIn <= totalAmountIn, "ERR_ACTUAL_IN");
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");

        transferAll(tokenOut, totalAmountOut);
        transferAll(tokenIn, getBalance(address(TI)));
    }

    function batchSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn
    ) public payable returns (uint256 totalAmountIn) {
        return
            batchSwapExactOutRefer(
                swaps,
                tokenIn,
                tokenOut,
                maxTotalAmountIn,
                address(0x0)
            );
    }

    function batchSwapExactOutRefer(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn,
        address referrer
    ) public payable nonReentrant returns (uint256 totalAmountIn) {
        require(
            swaps.length >= MIN_BATCH_SWAPS && swaps.length <= MAX_BATCH_SWAPS,
            "ERR_BATCH_COUNT"
        );

        IERC20 TI = IERC20(tokenIn);
        if (transferFromAllTo(TI, maxTotalAmountIn, address(this))) {
            TI = IERC20(address(weth));
        }

        IERC20 TO = IERC20(tokenOut);
        if (tokenOut == ETH_ADDR) {
            TO = IERC20(address(weth));
        }
        require(TI != TO, "ERR_SAME_TOKEN");

        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            IXPool pool = IXPool(swap.pool);

            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.safeApprove(swap.pool, 0);
                TI.safeApprove(swap.pool, MAX);
            }

            (uint256 tokenAmountIn, ) =
                pool.swapExactAmountOutRefer(
                    address(TI),
                    swap.tokenInParam,
                    address(TO),
                    swap.tokenOutParam,
                    swap.maxPrice,
                    referrer
                );
            totalAmountIn = tokenAmountIn.badd(totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        transferAll(tokenOut, getBalance(tokenOut));
        transferAll(tokenIn, getBalance(address(TI)));
    }

    // Multihop Swap
    struct MSwap {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 swapAmount; // tokenInAmount / tokenOutAmount
        uint256 limitReturnAmount; // minAmountOut / maxAmountIn
        uint256 maxPrice;
    }

    function multihopBatchSwapExactIn(
        MSwap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut
    ) public payable returns (uint256 totalAmountOut) {
        return
            multihopBatchSwapExactInRefer(
                swapSequences,
                tokenIn,
                tokenOut,
                totalAmountIn,
                minTotalAmountOut,
                address(0x0)
            );
    }

    function multihopBatchSwapExactInRefer(
        MSwap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut,
        address referrer
    ) public payable nonReentrant returns (uint256 totalAmountOut) {
        require(
            swapSequences.length >= MIN_BATCH_SWAPS &&
                swapSequences.length <= MAX_BATCH_SWAPS,
            "ERR_BATCH_COUNT"
        );

        transferFromAllTo(IERC20(tokenIn), totalAmountIn, address(this));

        uint256 actualTotalIn = 0;
        for (uint256 i = 0; i < swapSequences.length; i++) {
            require(tokenIn == swapSequences[i][0].tokenIn, "ERR_NOT_MATCH");
            actualTotalIn = actualTotalIn.badd(swapSequences[i][0].swapAmount);

            uint256 tokenAmountOut = 0;
            for (uint256 k = 0; k < swapSequences[i].length; k++) {
                MSwap memory swap = swapSequences[i][k];

                IERC20 SwapTokenIn = IERC20(swap.tokenIn);
                if (k == 1) {
                    // Makes sure that on the second swap the output of the first was used
                    // so there is not intermediate token leftover
                    swap.swapAmount = tokenAmountOut;
                }

                IXPool pool = IXPool(swap.pool);
                if (
                    SwapTokenIn.allowance(address(this), swap.pool) <
                    totalAmountIn
                ) {
                    SwapTokenIn.safeApprove(swap.pool, 0);
                    SwapTokenIn.safeApprove(swap.pool, MAX);
                }

                (tokenAmountOut, ) = pool.swapExactAmountInRefer(
                    swap.tokenIn,
                    swap.swapAmount,
                    swap.tokenOut,
                    swap.limitReturnAmount,
                    swap.maxPrice,
                    referrer
                );
            }
            // This takes the amountOut of the last swap
            totalAmountOut = tokenAmountOut.badd(totalAmountOut);
        }

        require(actualTotalIn <= totalAmountIn, "ERR_ACTUAL_IN");
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");

        transferAll(tokenOut, totalAmountOut);
        transferAll(tokenIn, getBalance(tokenIn));
    }

    function multihopBatchSwapExactOut(
        MSwap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn
    ) public payable returns (uint256 totalAmountIn) {
        return
            multihopBatchSwapExactOutRefer(
                swapSequences,
                tokenIn,
                tokenOut,
                maxTotalAmountIn,
                address(0x0)
            );
    }

    function multihopBatchSwapExactOutRefer(
        MSwap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn,
        address referrer
    ) public payable nonReentrant returns (uint256 totalAmountIn) {
        require(
            swapSequences.length >= MIN_BATCH_SWAPS &&
                swapSequences.length <= MAX_BATCH_SWAPS,
            "ERR_BATCH_COUNT"
        );

        transferFromAllTo(IERC20(tokenIn), maxTotalAmountIn, address(this));

        for (uint256 i = 0; i < swapSequences.length; i++) {
            require(tokenIn == swapSequences[i][0].tokenIn, "ERR_NOT_MATCH");

            uint256 tokenAmountInFirstSwap = 0;
            // Specific code for a simple swap and a multihop (2 swaps in sequence)
            if (swapSequences[i].length == 1) {
                MSwap memory swap = swapSequences[i][0];
                IERC20 SwapTokenIn = IERC20(swap.tokenIn);

                IXPool pool = IXPool(swap.pool);
                if (
                    SwapTokenIn.allowance(address(this), swap.pool) <
                    maxTotalAmountIn
                ) {
                    SwapTokenIn.safeApprove(swap.pool, 0);
                    SwapTokenIn.safeApprove(swap.pool, MAX);
                }

                (tokenAmountInFirstSwap, ) = pool.swapExactAmountOutRefer(
                    swap.tokenIn,
                    swap.limitReturnAmount,
                    swap.tokenOut,
                    swap.swapAmount,
                    swap.maxPrice,
                    referrer
                );
            } else {
                // Consider we are swapping A -> B and B -> C. The goal is to buy a given amount
                // of token C. But first we need to buy B with A so we can then buy C with B
                // To get the exact amount of C we then first need to calculate how much B we'll need:
                uint256 intermediateTokenAmount;
                // This would be token B as described above
                MSwap memory secondSwap = swapSequences[i][1];
                IXPool poolSecondSwap = IXPool(secondSwap.pool);
                intermediateTokenAmount = poolSecondSwap.calcInGivenOut(
                    poolSecondSwap.getBalance(secondSwap.tokenIn),
                    poolSecondSwap.getDenormalizedWeight(secondSwap.tokenIn),
                    poolSecondSwap.getBalance(secondSwap.tokenOut),
                    poolSecondSwap.getDenormalizedWeight(secondSwap.tokenOut),
                    secondSwap.swapAmount,
                    poolSecondSwap.swapFee()
                );

                // Buy intermediateTokenAmount of token B with A in the first pool
                MSwap memory firstSwap = swapSequences[i][0];
                IERC20 FirstSwapTokenIn = IERC20(firstSwap.tokenIn);
                IXPool poolFirstSwap = IXPool(firstSwap.pool);
                if (
                    FirstSwapTokenIn.allowance(address(this), firstSwap.pool) <
                    MAX
                ) {
                    FirstSwapTokenIn.safeApprove(firstSwap.pool, 0);
                    FirstSwapTokenIn.safeApprove(firstSwap.pool, MAX);
                }

                (tokenAmountInFirstSwap, ) = poolFirstSwap.swapExactAmountOut(
                    firstSwap.tokenIn,
                    firstSwap.limitReturnAmount,
                    firstSwap.tokenOut,
                    intermediateTokenAmount, // This is the amount of token B we need
                    firstSwap.maxPrice
                );

                // Buy the final amount of token C desired
                IERC20 SecondSwapTokenIn = IERC20(secondSwap.tokenIn);
                if (
                    SecondSwapTokenIn.allowance(
                        address(this),
                        secondSwap.pool
                    ) < MAX
                ) {
                    SecondSwapTokenIn.safeApprove(secondSwap.pool, 0);
                    SecondSwapTokenIn.safeApprove(secondSwap.pool, MAX);
                }

                poolSecondSwap.swapExactAmountOut(
                    secondSwap.tokenIn,
                    secondSwap.limitReturnAmount,
                    secondSwap.tokenOut,
                    secondSwap.swapAmount,
                    secondSwap.maxPrice
                );
            }
            totalAmountIn = tokenAmountInFirstSwap.badd(totalAmountIn);
        }

        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        transferAll(tokenOut, getBalance(tokenOut));
        transferAll(tokenIn, getBalance(tokenIn));
    }

    // Pool Management
    function create(
        address factoryAddress,
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        uint256 swapFee,
        uint256 exitFee
    ) external payable nonReentrant returns (address) {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        // pool deduplication
        (bool exist, bytes32 sig) = xconfig.dedupPool(tokens, denorms);
        require(!exist, "ERR_POOL_EXISTS");

        // create new pool
        IXPool pool = IXFactory(factoryAddress).newXPool();
        bool hasETH = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (
                transferFromAllTo(IERC20(tokens[i]), balances[i], address(pool))
            ) {
                hasETH = true;
                pool.bind(address(weth), denorms[i]);
            } else {
                pool.bind(tokens[i], denorms[i]);
            }
        }
        require(msg.value == 0 || hasETH, "ERR_INVALID_PAY");
        pool.setExitFee(exitFee);
        pool.finalize(swapFee);

        xconfig.addPoolSig(sig, address(pool));
        pool.transfer(msg.sender, pool.balanceOf(address(this)));

        return address(pool);
    }

    function joinPool(
        address poolAddress,
        uint256 poolAmountOut,
        uint256[] calldata maxAmountsIn
    ) external payable nonReentrant {
        IXPool pool = IXPool(poolAddress);

        address[] memory tokens = pool.getFinalTokens();
        require(maxAmountsIn.length == tokens.length, "ERR_LENGTH_MISMATCH");

        bool hasEth = false;
        for (uint8 i = 0; i < tokens.length; i++) {
            if (msg.value > 0 && tokens[i] == address(weth)) {
                transferFromAllAndApprove(
                    ETH_ADDR,
                    maxAmountsIn[i],
                    poolAddress
                );
                hasEth = true;
            } else {
                transferFromAllAndApprove(
                    tokens[i],
                    maxAmountsIn[i],
                    poolAddress
                );
            }
        }
        require(msg.value == 0 || hasEth, "ERR_INVALID_PAY");
        pool.joinPool(poolAmountOut, maxAmountsIn);
        for (uint8 i = 0; i < tokens.length; i++) {
            if (hasEth && tokens[i] == address(weth)) {
                transferAll(ETH_ADDR, getBalance(ETH_ADDR));
            } else {
                transferAll(tokens[i], getBalance(tokens[i]));
            }
        }
        pool.transfer(msg.sender, pool.balanceOf(address(this)));
    }

    function joinswapExternAmountIn(
        address poolAddress,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external payable nonReentrant {
        IXPool pool = IXPool(poolAddress);

        bool hasEth = false;
        if (transferFromAllAndApprove(tokenIn, tokenAmountIn, poolAddress)) {
            hasEth = true;
        }
        require(msg.value == 0 || hasEth, "ERR_INVALID_PAY");

        if (hasEth) {
            uint256 poolAmountOut =
                pool.joinswapExternAmountIn(
                    address(weth),
                    tokenAmountIn,
                    minPoolAmountOut
                );
            pool.transfer(msg.sender, poolAmountOut);
        } else {
            uint256 poolAmountOut =
                pool.joinswapExternAmountIn(
                    tokenIn,
                    tokenAmountIn,
                    minPoolAmountOut
                );
            pool.transfer(msg.sender, poolAmountOut);
        }
    }

    // Internal
    function getBalance(address token) internal view returns (uint256) {
        if (token == ETH_ADDR) {
            return weth.balanceOf(address(this));
        }
        return IERC20(token).balanceOf(address(this));
    }

    function transferAll(address token, uint256 amount)
        internal
        returns (bool)
    {
        if (amount == 0) {
            return true;
        }
        if (token == ETH_ADDR) {
            weth.withdraw(amount);
            (bool xfer, ) = msg.sender.call.value(amount).gas(9100)("");
            require(xfer, "ERR_ETH_FAILED");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        return true;
    }

    function transferFromAllTo(
        IERC20 token,
        uint256 amount,
        address to
    ) internal returns (bool hasETH) {
        hasETH = false;
        if (address(token) == ETH_ADDR) {
            require(amount == msg.value, "ERR_TOKEN_AMOUNT");
            weth.deposit.value(amount)();
            if (to != address(this)) {
                weth.transfer(to, amount);
            }
            hasETH = true;
        } else {
            token.safeTransferFrom(msg.sender, to, amount);
        }
    }

    function transferFromAllAndApprove(
        address token,
        uint256 amount,
        address spender
    ) internal returns (bool hasETH) {
        hasETH = false;
        if (token == ETH_ADDR) {
            require(amount == msg.value, "ERR_TOKEN_AMOUNT");
            weth.deposit.value(amount)();
            if (weth.allowance(address(this), spender) < amount) {
                IERC20(address(weth)).safeApprove(spender, 0);
                IERC20(address(weth)).safeApprove(spender, amount);
            }
            hasETH = true;
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            if (IERC20(token).allowance(address(this), spender) < amount) {
                IERC20(token).safeApprove(spender, 0);
                IERC20(token).safeApprove(spender, amount);
            }
        }
    }
}

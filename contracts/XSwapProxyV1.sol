pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interface/IXPool.sol";
import "./interface/IXFactory.sol";
import "./interface/IXConfig.sol";

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
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BONE = 10**18;
    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    uint256 public constant MIN_BATCH_SWAPS = 1;
    uint256 public constant MAX_BATCH_SWAPS = 5;

    // WETH9
    IWETH weth;

    IXConfig public xconfig;

    // Swap
    struct Swap {
        address pool;
        uint256 tokenInParam; // tokenInAmount / maxAmountIn / limitAmountIn
        uint256 tokenOutParam; // minAmountOut / tokenAmountOut / limitAmountOut
        uint256 maxPrice;
    }

    constructor(address _weth, address _xconfig) public {
        weth = IWETH(_weth);
        xconfig = IXConfig(_xconfig);
    }

    function() external payable {}

    // Swap
    function batchSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut
    ) public payable nonReentrant returns (uint256 totalAmountOut) {
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
        IERC20 TO = IERC20(tokenOut);

        transferFromAllTo(TI, totalAmountIn, address(this));

        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            IXPool pool = IXPool(swap.pool);

            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.safeApprove(swap.pool, uint256(-1));
            }

            (uint256 tokenAmountOut, ) =
                pool.swapExactAmountInRefer(
                    tokenIn,
                    swap.tokenInParam,
                    tokenOut,
                    swap.tokenOutParam,
                    swap.maxPrice,
                    referrer
                );
            totalAmountOut = tokenAmountOut.add(totalAmountOut);
        }

        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");

        transferAll(TO, totalAmountOut);
        transferAll(TI, getBalance(tokenIn));
        return totalAmountOut;
    }

    function batchSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn
    ) public payable nonReentrant returns (uint256 totalAmountIn) {
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
        IERC20 TO = IERC20(tokenOut);

        transferFromAllTo(TI, maxTotalAmountIn, address(this));

        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            IXPool pool = IXPool(swap.pool);

            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.safeApprove(swap.pool, uint256(-1));
            }

            (uint256 tokenAmountIn, ) =
                pool.swapExactAmountOutRefer(
                    tokenIn,
                    swap.tokenInParam,
                    tokenOut,
                    swap.tokenOutParam,
                    swap.maxPrice,
                    referrer
                );
            totalAmountIn = tokenAmountIn.add(totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        transferAll(TO, getBalance(tokenOut));
        transferAll(TI, getBalance(tokenIn));
    }

    // Pool Management
    function create(
        address factoryAddress,
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
<<<<<<< HEAD
        uint256 swapFee,
        uint256 poolExpiryBlockHeight
    ) external payable nonReentrant returns (IXPool pool) {
=======
        uint256 swapFee
    ) external payable nonReentrant returns (address) {
>>>>>>> master
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        // check pool exist
        (bool exist, bytes32 sig) = xconfig.hasPool(tokens, denorms);
        require(!exist, "ERR_POOL_EXISTS");

        // create new pool
        IXFactory factory = IXFactory(factoryAddress);
        IXPool pool = factory.newXPool();
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
        pool.finalize(swapFee);

<<<<<<< HEAD
        if (expiryBlockHeight > 0) {
            pool.setExpery(expiryBlockHeight);
        }

        _pools[sig] = true;
=======
        xconfig.addPoolSig(sig);
>>>>>>> master
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
        for (uint256 i = 0; i < tokens.length; i++) {
            if (msg.value > 0 && tokens[i] == address(weth)) {
                transferFromAllAndApprove(
                    xconfig.ethAddress(),
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
        for (uint256 i = 0; i < tokens.length; i++) {
            if (hasEth) {
                transferAll(
                    IERC20(xconfig.ethAddress()),
                    getBalance(xconfig.ethAddress())
                );
            } else {
                transferAll(IERC20(tokens[i]), getBalance(tokens[i]));
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
        if (token == xconfig.ethAddress()) {
            return weth.balanceOf(address(this));
        }
        return IERC20(token).balanceOf(address(this));
    }

    function transferAll(IERC20 token, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return true;
        }
        if (address(token) == xconfig.ethAddress()) {
            weth.withdraw(amount);
            (bool xfer, ) = msg.sender.call.value(amount)("");
            require(xfer, "ERR_ETH_FAILED");
        } else {
            token.safeTransfer(msg.sender, amount);
        }
        return true;
    }

    function transferFromAllTo(
        IERC20 token,
        uint256 amount,
        address to
    ) internal returns (bool hasETH) {
        hasETH = false;
        if (address(token) == xconfig.ethAddress()) {
            require(amount == msg.value, "ERR_TOKEN_AMOUNT");
            weth.deposit.value(amount)();
            weth.transfer(to, amount);
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
        if (token == xconfig.ethAddress()) {
            require(amount == msg.value, "ERR_TOKEN_AMOUNT");
            weth.deposit.value(amount)();
            if (weth.allowance(address(this), spender) > 0) {
                IERC20(address(weth)).safeApprove(address(spender), 0);
            }
            IERC20(address(weth)).safeApprove(spender, amount);
            hasETH = true;
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            if (IERC20(token).allowance(address(this), spender) > 0) {
                IERC20(token).safeApprove(spender, 0);
            }
            IERC20(token).safeApprove(spender, amount);
        }
    }
}

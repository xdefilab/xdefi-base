pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

contract PoolInterface {
    function swapExactAmountIn(
        address,
        uint256,
        address,
        uint256,
        uint256,
        address
    ) external returns (uint256, uint256);

    function swapExactAmountOut(
        address,
        uint256,
        address,
        uint256,
        uint256,
        address
    ) external returns (uint256, uint256);
}

// WETH9
contract TokenInterface {
    function balanceOf(address) public returns (uint256);

    function allowance(address, address) public returns (uint256);

    function approve(address, uint256) public returns (bool);

    function transfer(address, uint256) public returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) public returns (bool);

    function deposit() public payable;

    function withdraw(uint256) public;
}

contract XSwapProxyV1 {
    struct Swap {
        address pool;
        uint256 tokenInParam; // tokenInAmount / maxAmountIn / limitAmountIn
        uint256 tokenOutParam; // minAmountOut / tokenAmountOut / limitAmountOut
        uint256 maxPrice;
    }

    event LOG_CALL(bytes4 indexed sig, address indexed caller, bytes data);

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    bool private _mutex;
    TokenInterface weth;

    constructor(address _weth) public {
        weth = TokenInterface(_weth);
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function batchSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut,
        address referrer
    ) public _logs_ _lock_ returns (uint256 totalAmountOut) {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(
            TI.transferFrom(msg.sender, address(this), totalAmountIn),
            "ERR_TRANSFER_FAILED"
        );
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];

            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountOut, ) = pool.swapExactAmountIn(
                tokenIn,
                swap.tokenInParam,
                tokenOut,
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        require(
            TO.transfer(msg.sender, TO.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        require(
            TI.transfer(msg.sender, TI.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        return totalAmountOut;
    }

    function batchSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 maxTotalAmountIn,
        address referrer
    ) public _logs_ _lock_ returns (uint256 totalAmountIn) {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(
            TI.transferFrom(msg.sender, address(this), maxTotalAmountIn),
            "ERR_TRANSFER_FAILED"
        );
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountIn, ) = pool.swapExactAmountOut(
                tokenIn,
                swap.tokenInParam,
                tokenOut,
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");
        require(
            TO.transfer(msg.sender, TO.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        require(
            TI.transfer(msg.sender, TI.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        return totalAmountIn;
    }

    function batchEthInSwapExactIn(
        Swap[] memory swaps,
        address tokenOut,
        uint256 minTotalAmountOut,
        address referrer
    ) public payable _logs_ _lock_ returns (uint256 totalAmountOut) {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (weth.allowance(address(this), swap.pool) < msg.value) {
                weth.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountOut, ) = pool.swapExactAmountIn(
                address(weth),
                swap.tokenInParam,
                tokenOut,
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        require(
            TO.transfer(msg.sender, TO.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer, ) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountOut;
    }

    function batchEthOutSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        uint256 totalAmountIn,
        uint256 minTotalAmountOut,
        address referrer
    ) public _logs_ _lock_ returns (uint256 totalAmountOut) {
        TokenInterface TI = TokenInterface(tokenIn);
        require(
            TI.transferFrom(msg.sender, address(this), totalAmountIn),
            "ERR_TRANSFER_FAILED"
        );
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountOut, ) = pool.swapExactAmountIn(
                tokenIn,
                swap.tokenInParam,
                address(weth),
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );

            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        uint256 wethBalance = weth.balanceOf(address(this));
        weth.withdraw(wethBalance);
        (bool xfer, ) = msg.sender.call.value(wethBalance)("");
        require(xfer, "ERR_ETH_FAILED");
        require(
            TI.transfer(msg.sender, TI.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        return totalAmountOut;
    }

    function batchEthInSwapExactOut(
        Swap[] memory swaps,
        address tokenOut,
        address referrer
    ) public payable _logs_ _lock_ returns (uint256 totalAmountIn) {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (weth.allowance(address(this), swap.pool) < msg.value) {
                weth.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountIn, ) = pool.swapExactAmountOut(
                address(weth),
                swap.tokenInParam,
                tokenOut,
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );

            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(
            TO.transfer(msg.sender, TO.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer, ) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountIn;
    }

    function batchEthOutSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        uint256 maxTotalAmountIn,
        address referrer
    ) public _logs_ _lock_ returns (uint256 totalAmountIn) {
        TokenInterface TI = TokenInterface(tokenIn);
        require(
            TI.transferFrom(msg.sender, address(this), maxTotalAmountIn),
            "ERR_TRANSFER_FAILED"
        );
        for (uint256 i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint256(-1));
            }
            (uint256 tokenAmountIn, ) = pool.swapExactAmountOut(
                tokenIn,
                swap.tokenInParam,
                address(weth),
                swap.tokenOutParam,
                swap.maxPrice,
                referrer
            );

            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");
        require(
            TI.transfer(msg.sender, TI.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        uint256 wethBalance = weth.balanceOf(address(this));
        weth.withdraw(wethBalance);
        (bool xfer, ) = msg.sender.call.value(wethBalance)("");
        require(xfer, "ERR_ETH_FAILED");
        return totalAmountIn;
    }

    function() external payable {}
}

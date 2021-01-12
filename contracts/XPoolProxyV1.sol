pragma solidity 0.5.17;

import "./IXPool.sol";
import "./IXFactory.sol";
import "./IERC20.sol";

//TODO: support ETH, support safeTransfer()
contract XPoolProxyV1 {
    uint256 public constant BONE = 10**18;
    uint256 public constant DEFAULT_SWAP_FEE = (3 * BONE) / 1000; // 0.1%

    mapping(bytes32 => bool) internal _pools;

    function create(
        IXFactory factory,
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        uint256 swapFee
    ) external returns (IXPool pool) {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");

        bytes memory poolInfo;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (i > 0) {
                require(tokens[i] > tokens[i - 1], "ERR_TOKENS_NOT_SORTED");
            }
            poolInfo = abi.encodePacked(poolInfo, tokens[i], denorms[i]);
        }
        bytes32 sig = keccak256(poolInfo);
        require(!_pools[sig], "ERR_POOL_EXISTS");

        pool = factory.newXPool();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            require(
                token.transferFrom(msg.sender, address(this), balances[i]),
                "ERR_TRANSFER_FAILED"
            );
            token.approve(address(pool), balances[i]);
            pool.bind(tokens[i], balances[i], denorms[i]);
        }

        pool.finalize(swapFee);
        require(
            pool.transfer(msg.sender, pool.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
        _pools[sig] = true;
        return pool;
    }

    function joinPool(
        IXPool pool,
        uint256 poolAmountOut,
        uint256[] calldata maxAmountsIn
    ) external {
        address[] memory tokens = pool.getFinalTokens();
        require(maxAmountsIn.length == tokens.length, "ERR_LENGTH_MISMATCH");

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            require(
                token.transferFrom(msg.sender, address(this), maxAmountsIn[i]),
                "ERR_TRANSFER_FAILED"
            );
            token.approve(address(pool), maxAmountsIn[i]);
        }
        pool.joinPool(poolAmountOut, maxAmountsIn);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            if (token.balanceOf(address(this)) > 0) {
                require(
                    token.transfer(msg.sender, token.balanceOf(address(this))),
                    "ERR_TRANSFER_FAILED"
                );
            }
        }
        require(
            pool.transfer(msg.sender, pool.balanceOf(address(this))),
            "ERR_TRANSFER_FAILED"
        );
    }

    function joinswapExternAmountIn(
        IXPool pool,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external {
        IERC20 token = IERC20(tokenIn);
        require(
            token.transferFrom(msg.sender, address(this), tokenAmountIn),
            "ERR_TRANSFER_FAILED"
        );
        token.approve(address(pool), tokenAmountIn);
        uint256 poolAmountOut =
            pool.joinswapExternAmountIn(
                tokenIn,
                tokenAmountIn,
                minPoolAmountOut
            );
        require(
            pool.transfer(msg.sender, poolAmountOut),
            "ERR_TRANSFER_FAILED"
        );
    }
}

pragma solidity 0.5.17;

import "./XVersion.sol";
import "./XConst.sol";
import "./XPToken.sol";
import "./lib/XMath.sol";
import "./lib/XNum.sol";
import "./interface/IXConfig.sol";

contract XPool is XApollo, XPToken, XConst {
    using XNum for uint256;

    //Swap Fees: 0.1%, 0.25%, 1%, 2.5%, 10%
    uint256[5] public SWAP_FEES = [
        BONE / 1000,
        (25 * BONE) / 10000,
        BONE / 100,
        (25 * BONE) / 1000,
        BONE / 10
    ];

    struct Record {
        bool bound; // is token bound to pool
        uint256 index; // private
        uint256 denorm; // denormalized weight
        uint256 balance;
    }

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    event LOG_REFER(
        address indexed caller,
        address indexed ref,
        address indexed tokenIn,
        uint256 fee
    );

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    event LOG_BIND(
        address indexed caller,
        address indexed token,
        uint256 denorm,
        uint256 balance
    );

    event LOG_UPDATE_SAFU(address indexed safu, uint256 fee);

    event LOG_EXIT_FEE(uint256 fee);

    event LOG_FINAL(uint256 swapFee);

    // anonymous event
    event LOG_CALL(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

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

    modifier _viewlock_() {
        require(!_mutex, "ERR_REENTRY");
        _;
    }

    bool private _mutex;

    address public controller; // has CONTROL role

    // `finalize` require CONTROL, `finalize` sets `can SWAP and can JOIN`
    bool public finalized;

    uint256 public swapFee;
    uint256 public exitFee;

    // SAFU address and fee
    address public SAFU;
    uint256 public safuFee;

    address[] internal _tokens;
    mapping(address => Record) internal _records;
    uint256 private _totalWeight;

    IXConfig public xconfig;
    address public origin;

    constructor(address _xconfig, address _controller) public {
        controller = _controller;
        origin = tx.origin;
        swapFee = SWAP_FEES[1];
        exitFee = EXIT_ZERO_FEE;
        finalized = false;
        xconfig = IXConfig(_xconfig);
        SAFU = xconfig.getSAFU();
        safuFee = xconfig.getSafuFee();
    }

    function isBound(address t) external view returns (bool) {
        return _records[t].bound;
    }

    function getNumTokens() external view returns (uint256) {
        return _tokens.length;
    }

    function getFinalTokens()
        external
        view
        _viewlock_
        returns (address[] memory tokens)
    {
        require(finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    function getDenormalizedWeight(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external
        view
        _viewlock_
        returns (uint256)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        uint256 denorm = _records[token].denorm;
        return denorm.bdiv(_totalWeight);
    }

    function getBalance(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function setController(address manager) external _logs_ {
        require(msg.sender == controller, "ERR_NOT_CONTROLLER");
        controller = manager;
    }

    function setExitFee(uint256 fee) external {
        require(!finalized, "ERR_IS_FINALIZED");
        require(msg.sender == controller, "ERR_NOT_CONTROLLER");
        require(fee <= xconfig.getMaxExitFee(), "INVALID_EXIT_FEE");
        exitFee = fee;
        emit LOG_EXIT_FEE(fee);
    }

    // allow to be updated by xconfig
    function updateSafu(address safu, uint256 fee) external {
        require(msg.sender == address(xconfig), "ERR_NOT_CONFIG");
        require(safu != address(0), "ERR_ZERO_ADDR");
        SAFU = safu;
        safuFee = fee;

        emit LOG_UPDATE_SAFU(safu, fee);
    }

    function bind(address token, uint256 denorm) external _lock_ {
        require(msg.sender == controller, "ERR_NOT_CONTROLLER");
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(!finalized, "ERR_IS_FINALIZED");

        require(_tokens.length < MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");

        uint256 balance = IERC20(token).balanceOf(address(this));

        uint256 decimal = 10**uint256(IERC20(token).decimals());
        require(decimal >= 10**6, "ERR_TOO_SMALL");

        // 0.000001 TOKEN
        require(balance >= decimal / MIN_BALANCE, "ERR_MIN_BALANCE");

        _totalWeight = _totalWeight.badd(denorm);
        require(_totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");

        _records[token] = Record({
            bound: true,
            index: _tokens.length,
            denorm: denorm,
            balance: balance
        });
        _tokens.push(token);

        emit LOG_BIND(msg.sender, token, denorm, balance);
    }

    // _swapFee must be one of SWAP_FEES
    function finalize(uint256 _swapFee) external _lock_ {
        require(msg.sender == controller, "ERR_NOT_CONTROLLER");
        require(!finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(_tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        require(_swapFee >= SWAP_FEES[0], "ERR_MIN_FEE");
        require(_swapFee <= SWAP_FEES[SWAP_FEES.length - 1], "ERR_MAX_FEE");

        bool found = false;
        for (uint256 i = 0; i < SWAP_FEES.length; i++) {
            if (_swapFee == SWAP_FEES[i]) {
                found = true;
                break;
            }
        }
        require(found, "ERR_INVALID_SWAP_FEE");
        swapFee = _swapFee;

        finalized = true;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);

        emit LOG_FINAL(swapFee);
    }

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token) external _logs_ _lock_ {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    function getSpotPrice(address tokenIn, address tokenOut)
        external
        view
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return
            XMath.calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                swapFee
            );
    }

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external
        view
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return
            XMath.calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                0
            );
    }

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
        external
        _lock_
    {
        require(finalized, "ERR_NOT_FINALIZED");
        require(maxAmountsIn.length == _tokens.length, "ERR_LENGTH_MISMATCH");

        uint256 poolTotal = totalSupply();
        uint256 ratio = poolAmountOut.bdiv(poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountIn = ratio.bmul(bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance = (_records[t].balance).badd(tokenAmountIn);
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
        external
        _lock_
    {
        require(finalized, "ERR_NOT_FINALIZED");
        require(minAmountsOut.length == _tokens.length, "ERR_LENGTH_MISMATCH");

        // min pool amount
        require(poolAmountIn >= MIN_POOL_AMOUNT, "ERR_MIN_AMOUNT");

        uint256 poolTotal = totalSupply();
        uint256 _exitFee = poolAmountIn.bmul(exitFee);
        uint256 pAiAfterExitFee = poolAmountIn.bsub(_exitFee);
        uint256 ratio = pAiAfterExitFee.bdiv(poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        // to origin
        _pullPoolShare(msg.sender, poolAmountIn);
        if (_exitFee > 0) {
            _pushPoolShare(origin, _exitFee);
        }
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = ratio.bmul(bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance = (_records[t].balance).bsub(tokenAmountOut);
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }
    }

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        return
            swapExactAmountInRefer(
                tokenIn,
                tokenAmountIn,
                tokenOut,
                minAmountOut,
                maxPrice,
                address(0x0)
            );
    }

    function swapExactAmountInRefer(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice,
        address referrer
    ) public _lock_ returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(finalized, "ERR_NOT_FINALIZED");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountIn <= (inRecord.balance).bmul(MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        uint256 spotPriceBefore =
            XMath.calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                swapFee
            );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = calcOutGivenIn(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountIn,
            swapFee
        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");
        require(
            spotPriceBefore <= tokenAmountIn.bdiv(tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);
        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        spotPriceAfter = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        uint256 _swapFee = tokenAmountIn.bmul(swapFee);

        // to referral
        uint256 referFee = 0;
        if (
            referrer != address(0) &&
            referrer != msg.sender &&
            referrer != tx.origin
        ) {
            referFee = _swapFee / 5; // 20% to referrer
            _pushUnderlying(tokenIn, referrer, referFee);
            emit LOG_REFER(msg.sender, referrer, tokenIn, referFee);
        }

        // to SAFU
        uint256 _safuFee = tokenAmountIn.bmul(safuFee);
        if (xconfig.isFarmPool(address(this))) {
            _safuFee = _swapFee.bsub(referFee);
        }
        _pushUnderlying(tokenIn, SAFU, _safuFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
        return (tokenAmountOut, spotPriceAfter);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter) {
        return
            swapExactAmountOutRefer(
                tokenIn,
                maxAmountIn,
                tokenOut,
                tokenAmountOut,
                maxPrice,
                address(0x0)
            );
    }

    function swapExactAmountOutRefer(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice,
        address referrer
    ) public _lock_ returns (uint256 tokenAmountIn, uint256 spotPriceAfter) {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(finalized, "ERR_NOT_FINALIZED");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountOut <= (outRecord.balance).bmul(MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        uint256 spotPriceBefore =
            XMath.calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                swapFee
            );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = calcInGivenOut(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountOut,
            swapFee
        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");
        require(
            spotPriceBefore <= tokenAmountIn.bdiv(tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);
        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        spotPriceAfter = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        uint256 _swapFee = tokenAmountIn.bmul(swapFee);

        // to referral
        uint256 referFee = 0;
        if (
            referrer != address(0) &&
            referrer != msg.sender &&
            referrer != tx.origin
        ) {
            referFee = _swapFee / 5; // 20% to referrer
            _pushUnderlying(tokenIn, referrer, referFee);
            emit LOG_REFER(msg.sender, referrer, tokenIn, referFee);
        }

        // to SAFU
        uint256 _safuFee = tokenAmountIn.bmul(safuFee);
        if (xconfig.isFarmPool(address(this))) {
            _safuFee = _swapFee.bsub(referFee);
        }
        _pushUnderlying(tokenIn, SAFU, _safuFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
        return (tokenAmountIn, spotPriceAfter);
    }

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external _lock_ returns (uint256 poolAmountOut) {
        require(finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(
            tokenAmountIn <= (_records[tokenIn].balance).bmul(MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        Record storage inRecord = _records[tokenIn];

        poolAmountOut = XMath.calcPoolOutGivenSingleIn(
            inRecord.balance,
            inRecord.denorm,
            _totalSupply,
            _totalWeight,
            tokenAmountIn,
            swapFee
        );

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        // to SAFU
        uint256 _safuFee = tokenAmountIn.bmul(safuFee);
        if (xconfig.isFarmPool(address(this))) {
            _safuFee = tokenAmountIn.bmul(swapFee);
        }
        _pushUnderlying(tokenIn, SAFU, _safuFee);
        _pushPoolShare(msg.sender, poolAmountOut);
        return poolAmountOut;
    }

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external _logs_ _lock_ returns (uint256 tokenAmountOut) {
        require(finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        // min pool amount
        require(poolAmountIn >= MIN_POOL_AMOUNT, "ERR_MIN_AMOUNT");

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = XMath.calcSingleOutGivenPoolIn(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountIn,
            swapFee
        );

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(
            tokenAmountOut <= (_records[tokenOut].balance).bmul(MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        // to origin
        uint256 _exitFee = poolAmountIn.bmul(exitFee);
        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn.bsub(_exitFee));
        if (_exitFee > 0) {
            _pushPoolShare(origin, _exitFee);
        }

        // to SAFU
        uint256 _safuFee = tokenAmountOut.bmul(safuFee);
        if (xconfig.isFarmPool(address(this))) {
            _safuFee = tokenAmountOut.bmul(swapFee);
        }
        _pushUnderlying(tokenOut, SAFU, _safuFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut.bsub(_safuFee));
        return tokenAmountOut;
    }

    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 _swapFee
    ) public pure returns (uint256) {
        return
            XMath.calcOutGivenIn(
                tokenBalanceIn,
                tokenWeightIn,
                tokenBalanceOut,
                tokenWeightOut,
                tokenAmountIn,
                _swapFee
            );
    }

    function calcInGivenOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut,
        uint256 _swapFee
    ) public pure returns (uint256) {
        return
            XMath.calcInGivenOut(
                tokenBalanceIn,
                tokenWeightIn,
                tokenBalanceOut,
                tokenWeightOut,
                tokenAmountOut,
                _swapFee
            );
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety
    // Fixed ERC-20 transfer revert for some special token such as USDT
    function _pullUnderlying(
        address erc20,
        address from,
        uint256 amount
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) =
            erc20.call(
                abi.encodeWithSelector(0x23b872dd, from, address(this), amount)
            );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "ERC20_TRANSFER_FROM_FAILED"
        );
    }

    function _pushUnderlying(
        address erc20,
        address to,
        uint256 amount
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) =
            erc20.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "ERC20_TRANSFER_FAILED"
        );
    }

    function _pullPoolShare(address from, uint256 amount) internal {
        _move(from, address(this), amount);
    }

    function _pushPoolShare(address to, uint256 amount) internal {
        _move(address(this), to, amount);
    }

    function _mintPoolShare(uint256 amount) internal {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount) internal {
        _burn(amount);
    }
}

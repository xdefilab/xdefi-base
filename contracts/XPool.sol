pragma solidity 0.5.17;

import "./XVersion.sol";
import "./XConst.sol";
import "./XPToken.sol";
import "./lib/XMath.sol";
import "./lib/XNum.sol";

contract XPool is XApollo, XPToken, XConst {
    using XNum for uint256;

    //Swap Fees: 0.1%, 0.3%, 1%, 3%, 10%
    uint256[5] public SWAP_FEES = [
        BONE / 1000,
        (3 * BONE) / 1000,
        BONE / 100,
        (3 * BONE) / 100,
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

    //anonymous event
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

    modifier _viewlock_() {
        require(!_mutex, "ERR_REENTRY");
        _;
    }

    bool private _mutex;
    address public _controller; // has CONTROL role

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint256 public _swapFee;
    uint256 public _exitFee;
    bool public _finalized;

    address[] internal _tokens;
    mapping(address => Record) internal _records;
    uint256 private _totalWeight;

    // SAFU address
    address public _safu = 0x6db3A50418cE4B09c3133bb4fa57E4BE98E21662;
    address public _farmCreator = 0xa1cfB221AC318F751892345D87b9F4E91227Bc1C;

    // (tx.origin == _farmCreator) is xdex farm pool
    address public _origin;

    constructor() public {
        _controller = msg.sender;
        _origin = tx.origin;
        _swapFee = SWAP_FEES[1]; //0.3%
        _exitFee = EXIT_ZERO_FEE;
        _finalized = false;
    }

    function setExitFee(uint256 newFee) external _logs_ {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_exitFee <= MAX_EXIT_FEE, "INVALID_EXIT_FEE");
        _exitFee = newFee;
    }

    function isBound(address t) external view returns (bool) {
        return _records[t].bound;
    }

    function getNumTokens() external view returns (uint256) {
        return _tokens.length;
    }

    function getCurrentTokens()
        external
        view
        _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getFinalTokens()
        external
        view
        _viewlock_
        returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
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
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _controller = manager;
    }

    //Swap Fee must be one of {0.1%, 0.3%, 1%, 3%, 10%}
    function finalize(uint256 swapFee) external _logs_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(_tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        require(swapFee >= SWAP_FEES[0], "ERR_MIN_FEE");
        require(swapFee <= SWAP_FEES[4], "ERR_MAX_FEE");

        bool found = false;
        for (uint256 i = 0; i < SWAP_FEES.length; i++) {
            if (swapFee == SWAP_FEES[i]) {
                found = true;
                break;
            }
        }
        require(found, "ERR_INVALID_SWAP_FEE");
        _swapFee = swapFee;

        _finalized = true;
        //_publicSwap = true;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    )
        external
        _logs_
    // _lock_  Bind does not lock because it jumps to `rebind`, which does
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(_tokens.length < MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        _records[token] = Record({
            bound: true,
            index: _tokens.length,
            denorm: 0, // balance and denorm will be validated
            balance: 0 // and set by `rebind`
        });
        _tokens.push(token);
        rebind(token, balance, denorm);
    }

    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) public _logs_ _lock_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the denorm and totalWeight
        uint256 oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = _totalWeight.badd(denorm.bsub(oldWeight));
            require(_totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        } else if (denorm < oldWeight) {
            _totalWeight = _totalWeight.bsub(oldWeight.bsub(denorm));
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint256 oldBalance = _records[token].balance;
        _records[token].balance = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, balance.bsub(oldBalance));
        } else if (balance < oldBalance) {
            // In this case liquidity is being withdrawn, so charge EXIT_FEE
            uint256 tokenBalanceWithdrawn = oldBalance.bsub(balance);
            uint256 tokenExitFee = tokenBalanceWithdrawn.bmul(_exitFee).bdiv(
                BONE
            );
            _pushUnderlying(
                token,
                msg.sender,
                tokenBalanceWithdrawn.bsub(tokenExitFee)
            );
            _pushUnderlying(token, _safu, tokenExitFee);
        }
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
                _swapFee
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
        require(_finalized, "ERR_NOT_FINALIZED");

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
        require(_finalized, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 exitFee = poolAmountIn.bmul(_exitFee);
        uint256 pAiAfterExitFee = poolAmountIn.bsub(exitFee);
        uint256 ratio = pAiAfterExitFee.bdiv(poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        if (_exitFee > 0) {
            _pushPoolShare(_origin, exitFee);
        }
        _burnPoolShare(poolAmountIn);

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
        uint256 maxPrice,
        address referrer
    ) external _lock_ returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        //require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountIn <= (inRecord.balance).bmul(MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        uint256 spotPriceBefore = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = XMath.calcOutGivenIn(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountIn,
            _swapFee
        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);
        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        spotPriceAfter = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(
            spotPriceBefore <= tokenAmountIn.bdiv(tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        uint256 swapFee = tokenAmountIn.bmul(_swapFee).bdiv(BONE);

        //referral
        uint256 referFee = 0;
        if (
            referrer != address(0) &&
            referrer != msg.sender &&
            referrer != tx.origin
        ) {
            referFee = swapFee / 5; // 20%
            _pushUnderlying(tokenIn, referrer, referFee);
            emit LOG_REFER(msg.sender, referrer, tokenIn, referFee);
        }

        uint256 safuFee = 0;
        //is farm pool
        if (_farmCreator == _origin) {
            safuFee = swapFee.bsub(referFee); // 80%
        } else {
            safuFee = tokenAmountIn / 2000; // 0.05%
        }
        _pushUnderlying(tokenIn, _safu, safuFee);

        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
        return (tokenAmountOut, spotPriceAfter);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice,
        address referrer
    ) external _lock_ returns (uint256 tokenAmountIn, uint256 spotPriceAfter) {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        //require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountOut <= (outRecord.balance).bmul(MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        uint256 spotPriceBefore = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = XMath.calcInGivenOut(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountOut,
            _swapFee
        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);
        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        spotPriceAfter = XMath.calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(
            spotPriceBefore <= tokenAmountIn.bdiv(tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        uint256 swapFee = tokenAmountIn.bmul(_swapFee).bdiv(BONE);

        //referral
        uint256 referFee = 0;
        if (
            referrer != address(0) &&
            referrer != msg.sender &&
            referrer != tx.origin
        ) {
            referFee = swapFee / 5; // 20%
            _pushUnderlying(tokenIn, referrer, referFee);
            emit LOG_REFER(msg.sender, referrer, tokenIn, referFee);
        }

        uint256 safuFee = 0;
        //is farm pool
        if (_farmCreator == _origin) {
            safuFee = swapFee.bsub(referFee); // 80%
        } else {
            safuFee = tokenAmountIn / 2000; // 0.05%
        }
        _pushUnderlying(tokenIn, _safu, safuFee);

        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
        return (tokenAmountIn, spotPriceAfter);
    }

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external _lock_ returns (uint256 poolAmountOut) {
        require(_finalized, "ERR_NOT_FINALIZED");
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
            _swapFee
        );

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = (inRecord.balance).badd(tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        //TODO: in same function
        uint256 swapFee = 0;
        //is farm pool
        if (_farmCreator == _origin) {
            swapFee = tokenAmountIn.bmul(_swapFee).bdiv(BONE); // 100%
        } else {
            swapFee = tokenAmountIn / 2000; // 0.05%
        }
        _pushUnderlying(tokenIn, _safu, swapFee);

        _pushPoolShare(msg.sender, poolAmountOut);
        return poolAmountOut;
    }

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external _logs_ _lock_ returns (uint256 tokenAmountOut) {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = XMath.calcSingleOutGivenPoolIn(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountIn,
            _swapFee
        );

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(
            tokenAmountOut <= (_records[tokenOut].balance).bmul(MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        outRecord.balance = (outRecord.balance).bsub(tokenAmountOut);

        uint256 exitFee = poolAmountIn.bmul(_exitFee).bdiv(BONE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn.bsub(exitFee));
        if (exitFee > 0) {
            _pushPoolShare(_origin, exitFee);
        }

        uint256 swapFee = 0;
        //is farm pool
        if (_farmCreator == _origin) {
            swapFee = tokenAmountOut.bmul(_swapFee).bdiv(BONE); // 100%
        } else {
            swapFee = tokenAmountOut / 2000; // 0.05%
        }
        _pushUnderlying(tokenOut, _safu, swapFee);

        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
        return tokenAmountOut;
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
        (bool success, bytes memory data) = erc20.call(
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
        (bool success, bytes memory data) = erc20.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
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

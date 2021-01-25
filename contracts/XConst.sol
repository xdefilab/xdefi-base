pragma solidity 0.5.17;

contract XConst {
    uint256 public constant BONE = 10**18;

    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    uint256 public constant EXIT_ZERO_FEE = 0;

    uint256 public constant MIN_WEIGHT = BONE;
    uint256 public constant MAX_WEIGHT = BONE * 50;
    uint256 public constant MAX_TOTAL_WEIGHT = BONE * 50;

    // min effective value: 0.000001 TOKEN
    uint256 public constant MIN_BALANCE = 10**6;

    // BONE/(10**10) XPT
    uint256 public constant MIN_POOL_AMOUNT = 10**8;

    uint256 public constant INIT_POOL_SUPPLY = BONE * 100;

    uint256 public constant MAX_IN_RATIO = BONE / 2;
    uint256 public constant MAX_OUT_RATIO = (BONE / 3) + 1 wei;
}

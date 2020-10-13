pragma solidity 0.5.17;

import "./XVersion.sol";

contract XConst is XApollo {
    uint256 public constant BONE = 10**18;

    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    //Swap Fees: 0.1%, 0.3%, 1%, 3%, 10%
    uint256[5] public SWAP_FEES = [
        BONE / 1000,
        (3 * BONE) / 1000,
        BONE / 100,
        (3 * BONE) / 100,
        BONE / 10
    ];

    uint256 public constant MIN_FEE = BONE / 1000;
    uint256 public constant MAX_FEE = BONE / 10;

    //Secure Asset Fund for Users(SAFU)
    uint256 public constant SAFU_FEE = (5 * BONE) / 10000;

    uint256 public constant EXIT_ZERO_FEE = 0;
    uint256 public constant EXIT_VOTING_POOL_FEE = BONE / 100;

    uint256 public constant MIN_WEIGHT = BONE;
    uint256 public constant MAX_WEIGHT = BONE * 50;
    uint256 public constant MAX_TOTAL_WEIGHT = BONE * 50;
    uint256 public constant MIN_BALANCE = BONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY = BONE * 100;

    uint256 public constant MIN_BPOW_BASE = 1 wei;
    uint256 public constant MAX_BPOW_BASE = (2 * BONE) - 1 wei;
    uint256 public constant BPOW_PRECISION = BONE / 10**10;

    uint256 public constant MAX_IN_RATIO = BONE / 2;
    uint256 public constant MAX_OUT_RATIO = (BONE / 3) + 1 wei;
}

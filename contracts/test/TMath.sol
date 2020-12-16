pragma solidity 0.5.17;

import "../lib/XMath.sol";
import "../lib/XNum.sol";

// Contract to wrap internal functions for testing

contract TMath {
    function calc_btoi(uint256 a) external pure returns (uint256) {
        return XNum.btoi(a);
    }

    function calc_bfloor(uint256 a) external pure returns (uint256) {
        return XNum.bfloor(a);
    }

    function calc_badd(uint256 a, uint256 b) external pure returns (uint256) {
        return XNum.badd(a, b);
    }

    function calc_bsub(uint256 a, uint256 b) external pure returns (uint256) {
        return XNum.bsub(a, b);
    }

    function calc_bsubSign(uint256 a, uint256 b)
        external
        pure
        returns (uint256, bool)
    {
        return XNum.bsubSign(a, b);
    }

    function calc_bmul(uint256 a, uint256 b) external pure returns (uint256) {
        return XNum.bmul(a, b);
    }

    function calc_bdiv(uint256 a, uint256 b) external pure returns (uint256) {
        return XNum.bdiv(a, b);
    }

    function calc_bpowi(uint256 a, uint256 n) external pure returns (uint256) {
        return XNum.bpowi(a, n);
    }

    function calc_bpow(uint256 base, uint256 exp)
        external
        pure
        returns (uint256)
    {
        return XNum.bpow(base, exp);
    }

    function calc_bpowApprox(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) external pure returns (uint256) {
        return XNum.bpowApprox(base, exp, precision);
    }
}

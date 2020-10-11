// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.5.17;

import "../XMath.sol";
import "../XNum.sol";

// Contract to wrap internal functions for testing

contract TMath is XMath {
    function calc_btoi(uint256 a) external pure returns (uint256) {
        return btoi(a);
    }

    function calc_bfloor(uint256 a) external pure returns (uint256) {
        return bfloor(a);
    }

    function calc_badd(uint256 a, uint256 b) external pure returns (uint256) {
        return badd(a, b);
    }

    function calc_bsub(uint256 a, uint256 b) external pure returns (uint256) {
        return bsub(a, b);
    }

    function calc_bsubSign(uint256 a, uint256 b)
        external
        pure
        returns (uint256, bool)
    {
        return bsubSign(a, b);
    }

    function calc_bmul(uint256 a, uint256 b) external pure returns (uint256) {
        return bmul(a, b);
    }

    function calc_bdiv(uint256 a, uint256 b) external pure returns (uint256) {
        return bdiv(a, b);
    }

    function calc_bpowi(uint256 a, uint256 n) external pure returns (uint256) {
        return bpowi(a, n);
    }

    function calc_bpow(uint256 base, uint256 exp)
        external
        pure
        returns (uint256)
    {
        return bpow(base, exp);
    }

    function calc_bpowApprox(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) external pure returns (uint256) {
        return bpowApprox(base, exp, precision);
    }
}

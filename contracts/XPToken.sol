pragma solidity 0.5.17;

import "./XVersion.sol";
import "./lib/XNum.sol";
import "./interface/IERC20.sol";

// Highly opinionated token implementation
contract XTokenBase {
    using XNum for uint256;

    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed src, address indexed dst, uint256 amt);
    event Transfer(address indexed src, address indexed dst, uint256 amt);

    function _mint(uint256 amt) internal {
        _balance[address(this)] = (_balance[address(this)]).badd(amt);
        _totalSupply = _totalSupply.badd(amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint256 amt) internal {
        require(_balance[address(this)] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = (_balance[address(this)]).bsub(amt);
        _totalSupply = _totalSupply.bsub(amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(
        address src,
        address dst,
        uint256 amt
    ) internal {
        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[src] = (_balance[src]).bsub(amt);
        _balance[dst] = (_balance[dst]).badd(amt);
        emit Transfer(src, dst, amt);
    }
}

contract XPToken is XTokenBase, IERC20, XApollo {
    using XNum for uint256;

    string private _name = "XDeFi Pool Token";
    string private _symbol = "XPT";
    uint8 private _decimals = 18;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function allowance(address src, address dst) public view returns (uint256) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) public view returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt) public returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function transfer(address dst, uint256 amt) public returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) public returns (bool) {
        require(
            msg.sender == src || amt <= _allowance[src][msg.sender],
            "ERR_BTOKEN_BAD_CALLER"
        );
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != uint256(-1)) {
            _allowance[src][msg.sender] = (_allowance[src][msg.sender]).bsub(
                amt
            );
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

pragma solidity 0.5.17;

// Builds new XPools, logging their addresses and providing `isXPool(address) -> (bool)`

import "./XPool.sol";

contract XFactory is XApollo {
    address public core;

    mapping(address => bool) private _isPool;

    event LOG_NEW_POOL(address indexed caller, address indexed pool);
    event CoreTransferred(address indexed _core, address indexed _coreNew);

    modifier onlyCore() {
        require(msg.sender == core, "Not Authorized");
        _;
    }

    constructor() public {
        core = msg.sender;
    }

    function isPool(address b) external view returns (bool) {
        return _isPool[b];
    }

    function newXPool() external returns (XPool) {
        XPool xpool = new XPool();
        _isPool[address(xpool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(xpool));
        xpool.setController(msg.sender);
        return xpool;
    }

    function getCore() external view returns (address) {
        return core;
    }

    function setCore(address _core) public onlyCore {
        emit CoreTransferred(core, _core);
        core = _core;
    }

    function collect(XPool pool) external onlyCore {
        uint256 collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(core, collected);
        require(xfer, "ERR_ERC20_FAILED");
    }
}

pragma solidity 0.5.17;

// Builds new XPools, logging their addresses and providing `isPool(address) -> (bool)`
import "./XVersion.sol";
import "./XPool.sol";
import "./IXConfig.sol";

interface IXPoolCreator {
    function newXPool() external returns (XPool);
}

contract XFactory is XApollo {
    address public core;
    IXPoolCreator public xpoolCreator;

    mapping(address => bool) private _isPool;

    event LOG_NEW_POOL(address indexed caller, address indexed pool);
    event SET_CORE(address indexed core, address indexed coreNew);

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
        XPool xpool = xpoolCreator.newXPool();
        _isPool[address(xpool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(xpool));
        xpool.setController(msg.sender);
        return xpool;
    }

    function setCore(address _core) external onlyCore {
        core = _core;
        emit SET_CORE(core, _core);
    }

    function setPoolCreator(IXPoolCreator _xpoolCreator) external onlyCore {
        xpoolCreator = _xpoolCreator;
    }
}

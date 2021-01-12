pragma solidity 0.5.17;

// Builds new XPools, logging their addresses and providing `isPool(address) -> (bool)`
import "./XVersion.sol";
import "./XPool.sol";
import "./IXConfig.sol";

interface IXPoolCreator {
    function newXPool(address config, address controller)
        external
        returns (XPool);
}

contract XFactory is XApollo {
    IXPoolCreator public creator;
    IXConfig public xconfig;

    mapping(address => bool) private _isPool;

    event LOG_NEW_POOL(address indexed caller, address indexed pool);
    event SET_CORE(address indexed core, address indexed _core);
    event SET_CONFIG(address indexed conf, address indexed _conf);
    event SET_XPOOL_CREATOR(address indexed creator, address indexed _creator);

    constructor(address _xconfig) public {
        require(_xconfig != address(0), "ERR_ZERO_ADDR");

        xconfig = IXConfig(_xconfig);
    }

    function isPool(address b) external view returns (bool) {
        return _isPool[b];
    }

    function newXPool() external returns (XPool) {
        require(address(creator) != address(0), "ERR_ZERO_ADDR");

        XPool xpool = creator.newXPool(address(xconfig), msg.sender);
        _isPool[address(xpool)] = true;

        emit LOG_NEW_POOL(msg.sender, address(xpool));
        return xpool;
    }

    function setPoolCreator(address _creator) external {
        require(msg.sender == xconfig.getCore(), "ERR_CORE_AUTH");
        require(_creator != address(0), "ERR_ZERO_ADDR");

        emit SET_XPOOL_CREATOR(address(creator), _creator);
        creator = IXPoolCreator(_creator);
    }

    function setConfig(address _config) external {
        require(msg.sender == xconfig.getCore(), "ERR_CORE_AUTH");
        require(_config != address(0), "ERR_ZERO_ADDR");

        emit SET_CONFIG(address(xconfig), _config);
        xconfig = IXConfig(_config);
    }
}

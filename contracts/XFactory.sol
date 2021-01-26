pragma solidity 0.5.17;

// Builds new XPools, logging their addresses and providing `isPool(address) -> (bool)`
import "./XVersion.sol";
import "./XPool.sol";
import "./interface/IXConfig.sol";

interface IXPoolCreator {
    function newXPool(address config, address controller)
        external
        returns (XPool);
}

contract XFactory is XApollo {
    IXPoolCreator public xcreator;
    IXConfig public xconfig;

    mapping(address => bool) private _isPool;

    event LOG_NEW_POOL(address indexed caller, address indexed pool);
    event SET_XPOOL_CREATOR(
        address indexed creator,
        address indexed creatorNew
    );

    constructor(address _config, address _creator) public {
        xconfig = IXConfig(_config);
        xcreator = IXPoolCreator(_creator);
    }

    function isPool(address b) external view returns (bool) {
        return _isPool[b];
    }

    function newXPool() external returns (XPool) {
        XPool xpool = xcreator.newXPool(address(xconfig), msg.sender);
        _isPool[address(xpool)] = true;

        emit LOG_NEW_POOL(msg.sender, address(xpool));
        return xpool;
    }

    function setPoolCreator(address _creator) external {
        require(msg.sender == xconfig.getCore(), "ERR_NOT_AUTH");
        require(_creator != address(0), "ERR_ZERO_ADDR");

        emit SET_XPOOL_CREATOR(address(xcreator), _creator);
        xcreator = IXPoolCreator(_creator);
    }
}

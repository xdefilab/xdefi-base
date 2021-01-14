pragma solidity 0.5.17;

contract XConfig {
    address private core;

    // Secure Asset Fund for Users(SAFU) address
    address private safu = address(0x6db3A50418cE4B09c3133bb4fa57E4BE98E21662);
    uint256 public SAFU_FEE = (5 * BONE) / 10000;

    // XDEX Farm Pool Creator
    address private farmPoolCreator =
        address(0xa1cfB221AC318F751892345D87b9F4E91227Bc1C);

    uint256 public constant BONE = 10**18;
    uint256 public maxExitFee = BONE / 1000; // 0.1%

    event INIT_Config(address indexed config);
    event SET_CORE(address indexed core, address indexed coreNew);
    event SET_SAFU(address indexed safu, address indexed safuNew);
    event SET_FARM_CREATOR(
        address indexed farmPoolCreator,
        address indexed creatorNew
    );
    event SET_SAFU_FEE(uint256 indexed fee, uint256 indexed feeNew);

    modifier onlyCore() {
        require(msg.sender == core, "ERR_CORE_AUTH");
        _;
    }

    constructor() public {
        core = msg.sender;
        emit INIT_Config(address(this));
    }

    function getCore() external view returns (address) {
        return core;
    }

    function getSAFU() external view returns (address) {
        return safu;
    }

    function getFarmCreator() external view returns (address) {
        return farmPoolCreator;
    }

    function getMaxExitFee() external view returns (uint256) {
        return maxExitFee;
    }

    function getSafuFee() external view returns (uint256) {
        return SAFU_FEE;
    }

    /**
     * @dev returns the address used within the protocol to identify ETH
     * @return the address assigned to ETH
     */
    function ethAddress() external pure returns (address) {
        return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    function setCore(address _core) external onlyCore {
        require(_core != address(0), "ERR_ZERO_ADDR");
        emit SET_CORE(core, _core);
        core = _core;
    }

    function setSAFU(address _safu) external onlyCore {
        require(_safu != address(0), "ERR_ZERO_ADDR");
        emit SET_SAFU(safu, _safu);
        safu = _safu;
    }

    function setFarmCreator(address _user) external onlyCore {
        require(_user != address(0), "ERR_ZERO_ADDR");
        emit SET_FARM_CREATOR(farmPoolCreator, _user);
        farmPoolCreator = _user;
    }

    function setMaxExitFee(uint256 _fee) external onlyCore {
        require(_fee <= (BONE / 10), "INVALID_EXIT_FEE");
        maxExitFee = _fee;
    }

    function setSafuFee(uint256 _fee) external onlyCore {
        require(_fee <= (BONE / 10), "INVALID_SAFU_FEE");
        emit SET_SAFU_FEE(SAFU_FEE, _fee);
        SAFU_FEE = _fee;
    }
}

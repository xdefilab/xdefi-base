pragma solidity 0.5.17;

import "./XConst.sol";
import "./interface/IXPool.sol";
import "./interface/IERC20.sol";
import "./lib/Address.sol";
import "./lib/SafeERC20.sol";
import "./lib/XNum.sol";

/**
1. SAFU is a multi-sig account
2. SAFU is the core of XConfig contract instance
3. DEV firstly deploys XConfig contract, then setups the xconfig.core and xconfig.safu to SAFU with setSAFU() and setCore() 
*/
contract XConfig is XConst {
    using XNum for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    address private core;

    // Secure Asset Fund for Users(SAFU) address
    address private safu;
    uint256 public SAFU_FEE = (5 * BONE) / 10000; // 0.05%

    // Swap Proxy Address
    address private swapProxy;

    // Check Farm Pool
    mapping(address => bool) internal farmPools;

    // sorted pool sigs for pool deduplication
    // key: keccak256(tokens[i], norms[i]), value: pool_exists
    mapping(bytes32 => bool) internal poolSigs;
    uint256 public poolSigCount;

    uint256 public maxExitFee = BONE / 1000; // 0.1%

    event INIT_SAFU(address indexed addr);
    event SET_CORE(address indexed core, address indexed coreNew);

    event SET_SAFU(address indexed safu, address indexed safuNew);
    event SET_SAFU_FEE(uint256 indexed fee, uint256 indexed feeNew);

    event SET_PROXY(address indexed proxy, address indexed proxyNew);

    event ADD_POOL_SIG(address indexed caller, bytes32 sig);
    event RM_POOL_SIG(address indexed caller, bytes32 sig);

    event ADD_FARM_POOL(address indexed pool);
    event RM_FARM_POOL(address indexed pool);

    event COLLECT(address indexed token, uint256 amount);

    modifier onlyCore() {
        require(msg.sender == core, "ERR_CORE_AUTH");
        _;
    }

    constructor() public {
        core = msg.sender;
        safu = address(this);
        emit INIT_SAFU(address(this));
    }

    function getCore() external view returns (address) {
        return core;
    }

    function getSAFU() external view returns (address) {
        return safu;
    }

    function getMaxExitFee() external view returns (uint256) {
        return maxExitFee;
    }

    function getSafuFee() external view returns (uint256) {
        return SAFU_FEE;
    }

    function getSwapProxy() external view returns (address) {
        return swapProxy;
    }

    /**
     * @dev returns the address used within the protocol to identify ETH
     * @return the address assigned to ETH
     */
    function ethAddress() external pure returns (address) {
        return address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    // check pool existence which has the same tokens(sorted by address) and weights
    // the decimals of denorms will allways between [10**18, 50 * 10**18]
    function hasPool(address[] calldata tokens, uint256[] calldata denorms)
        external
        view
        returns (bool exist, bytes32 sig)
    {
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        uint256 totalWeight = 0;
        for (uint8 i = 0; i < tokens.length; i++) {
            totalWeight = totalWeight.badd(denorms[i]);
        }

        bytes memory poolInfo;
        for (uint8 i = 0; i < tokens.length; i++) {
            if (i > 0) {
                require(tokens[i] > tokens[i - 1], "ERR_TOKENS_NOT_SORTED");
            }
            //normalized weight (multiplied by 100)
            uint256 nWeight = denorms[i].bmul(100).bdiv(totalWeight);
            poolInfo = abi.encodePacked(poolInfo, tokens[i], nWeight);
        }
        sig = keccak256(poolInfo);

        exist = poolSigs[sig];
    }

    function setCore(address _core) external onlyCore {
        require(_core != address(0), "ERR_ZERO_ADDR");
        emit SET_CORE(core, _core);
        core = _core;
    }

    function setSAFU(address _safu) external onlyCore {
        emit SET_SAFU(safu, _safu);
        safu = _safu;
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

    function setSwapProxy(address _proxy) external onlyCore {
        require(_proxy != address(0), "ERR_ZERO_ADDR");
        emit SET_PROXY(swapProxy, _proxy);
        swapProxy = _proxy;
    }

    // add pool's sig
    // only allow called by swapProxy
    function addPoolSig(bytes32 sig) external {
        require(msg.sender == swapProxy, "ERR_NOT_SWAPPROXY");
        require(sig != 0, "ERR_NOT_SIG");
        poolSigs[sig] = true;
        poolSigCount = poolSigCount.badd(1);

        emit ADD_POOL_SIG(msg.sender, sig);
    }

    // remove pool's sig
    // only allow called by swapProxy
    function removePoolSig(bytes32 sig) external {
        require(msg.sender == swapProxy, "ERR_NOT_SWAPPROXY");
        require(sig != 0, "ERR_NOT_SIG");
        poolSigs[sig] = false;
        poolSigCount = poolSigCount.bsub(1);

        emit RM_POOL_SIG(msg.sender, sig);
    }

    function isFarmPool(address pool) external view returns (bool) {
        return farmPools[pool];
    }

    //list farm pool
    function addFarmPool(address pool) external onlyCore {
        require(pool != address(0), "ERR_ZERO_ADDR");
        require(!farmPools[pool], "ERR_IS_FARMPOOL");
        farmPools[pool] = true;

        emit ADD_FARM_POOL(pool);
    }

    //delist farm pool
    function removeFarmPool(address pool) external onlyCore {
        require(pool != address(0), "ERR_ZERO_ADDR");
        require(farmPools[pool], "ERR_NOT_FARMPOOL");
        farmPools[pool] = false;

        emit RM_FARM_POOL(pool);
    }

    // update SAFU address and SAFE_FEE to pools
    function updateSafu(address[] calldata pools) external onlyCore {
        require(pools.length > 0 && pools.length <= 30, "ERR_BATCH_COUNT");

        for (uint256 i = 0; i < pools.length; i++) {
            require(Address.isContract(pools[i]), "ERR_NOT_CONTRACT");

            IXPool pool = IXPool(pools[i]);
            pool.updateSafu(safu, SAFU_FEE);
        }
    }

    // update isFarmPool status to pools
    function updateFarm(address[] calldata pools, bool isFarm)
        external
        onlyCore
    {
        require(pools.length > 0 && pools.length <= 30, "ERR_BATCH_COUNT");

        for (uint256 i = 0; i < pools.length; i++) {
            require(Address.isContract(pools[i]), "ERR_NOT_CONTRACT");

            IXPool pool = IXPool(pools[i]);
            pool.updateFarm(isFarm);
        }
    }

    // collect any tokens in this contract to safu
    function collect(address token) external onlyCore {
        IERC20 TI = IERC20(token);

        uint256 collected = TI.balanceOf(address(this));
        TI.safeTransfer(safu, collected);

        emit COLLECT(token, collected);
    }
}

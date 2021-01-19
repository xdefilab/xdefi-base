pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interface/IXPool.sol";
import "./XConst.sol";

// https://github.com/xdefilab/xdefi-governance-token/blob/master/contracts/XDEX.sol
interface IXDEX {
    function burnForSelf(uint256 amount) external;
}

// https://github.com/xdefilab/xdefi-governance-token/blob/master/contracts/FarmMaster.sol
interface IFarmMaster {
    // Deposit LP tokens to FarmMaster for XDEX allocation.
    function deposit(
        uint256 pid,
        IERC20 lpToken,
        uint256 amount
    ) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(
        uint256 pid,
        IERC20 lpToken,
        uint256 amount
    ) external;
}

contract XConfig is XConst {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    address private core;

    // XDEX Token!
    address public constant XDEX =
        address(0xaDBc525ace6ed9c5195071f29036e7ecCd1DC158); // kovan
    // mainnet

    // Secure Asset Fund for Users(SAFU) address
    address private safu;
    uint256 public SAFU_FEE = (5 * BONE) / 10000;

    // XDEX Farm Pool Creator
    address private farmPoolCreator;

    // Swap Proxy Address
    address private swapProxy;

    // Check Farm Pool
    mapping(address => bool) internal farmPools;
    //isFarmPool
    //addFarmPool
    //removeFarmPool

    // sorted pool sigs
    // key: keccak256(tokens[i], norms[i]), value: pool_exists
    mapping(bytes32 => bool) internal poolSigs;

    uint256 public maxExitFee = BONE / 1000; // 0.1%

    event INIT_SAFU(address indexed addr);
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
        safu = address(this);
        farmPoolCreator = address(0xa1cfB221AC318F751892345D87b9F4E91227Bc1C);
        emit INIT_SAFU(address(this));
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

    function XDEXAddress() external pure returns (address) {
        return XDEX;
    }

    // check pool existence which has the same tokens(sorted by address) and weights
    function hasPool(address[] memory tokens, uint256[] memory denorms)
        public
        view
        returns (bool exist, bytes32 sig)
    {
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        uint256 totalWeight = 0;
        for (uint8 i = 0; i < tokens.length; i++) {
            totalWeight = totalWeight.add(denorms[i]);
        }

        bytes memory poolInfo;
        for (uint8 i = 0; i < tokens.length; i++) {
            if (i > 0) {
                require(tokens[i] > tokens[i - 1], "ERR_TOKENS_NOT_SORTED");
            }
            //normalized weight (multiplied by 100)
            uint256 nWeight = denorms[i].mul(100).div(totalWeight);
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

    function setSwapProxy(address _proxy) external onlyCore {
        require(_proxy != address(0), "ERR_ZERO_ADDR");
        swapProxy = _proxy;
    }

    // add pool's sig
    function addPoolSig(bytes32 sig) external {
        require(msg.sender == swapProxy, "ERR_NOT_SWAPPROXY");
        require(sig != 0, "ERR_NOT_SIG");
        poolSigs[sig] = true;
    }

    function isFarmPool(address pool) external view returns (bool) {
        return farmPools[pool];
    }

    function addFarmPool(address pool) external onlyCore {
        require(pool != address(0), "ERR_ZERO_ADDR");
        require(!farmPools[pool], "ERR_IS_FARMPOOL");
        farmPools[pool] = true;
    }

    function removeFarmPool(address pool) external onlyCore {
        require(pool != address(0), "ERR_ZERO_ADDR");
        require(farmPools[pool], "ERR_NOT_FARMPOOL");
        farmPools[pool] = false;
    }

    // swap any token in SAFU to XDEX
    function convert(
        address pool,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 maxPrice
    )
        external
        onlyCore
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(msg.sender == tx.origin, "ERR_FROM_CONTRACT");

        IXPool xpool = IXPool(pool);
        require(xpool.isBound(tokenIn) && xpool.isBound(XDEX), "ERR_NOT_BOUND");

        //safe approve
        IERC20 TI = IERC20(tokenIn);
        if (TI.allowance(address(this), pool) > 0) {
            TI.safeApprove(pool, 0);
        }
        TI.safeApprove(pool, tokenAmountIn);

        //swap
        return
            xpool.swapExactAmountIn(tokenIn, tokenAmountIn, XDEX, 0, maxPrice);
    }

    // add SAFU's assets as liquidity to any pool, such as WETH-DAI-XDEX
    function joinPool(
        address pool,
        uint256 poolAmountOut,
        uint256[] calldata maxAmountsIn
    ) external onlyCore {
        require(Address.isContract(pool), "ERR_NOT_CONTRACT");
        IXPool xpool = IXPool(pool);

        //safe approve
        address[] memory tokens = xpool.getFinalTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 TI = IERC20(tokens[i]);
            if (TI.allowance(address(this), pool) > 0) {
                TI.safeApprove(pool, 0);
            }
            TI.safeApprove(pool, maxAmountsIn[i]);
        }

        xpool.joinPool(poolAmountOut, maxAmountsIn);
    }

    // remove SAFU's liquidity from any pool
    function exitPool(
        address pool,
        uint256 poolAmountIn,
        uint256[] calldata minAmountsOut
    ) external onlyCore {
        require(Address.isContract(pool), "ERR_NOT_CONTRACT");
        IXPool(pool).exitPool(poolAmountIn, minAmountsOut);
    }

    // burn xdex
    function burnForSelf(uint256 amount) external onlyCore {
        IXDEX(XDEX).burnForSelf(amount);
    }

    // deposit lp to farm pool
    function depositToFarm(
        address farmMaster,
        uint256 pid,
        IERC20 lpToken,
        uint256 amount
    ) external onlyCore {
        require(Address.isContract(farmMaster), "ERR_NOT_CONTRACT");

        //safe approve
        if (lpToken.allowance(address(this), farmMaster) > 0) {
            lpToken.safeApprove(farmMaster, 0);
        }
        lpToken.safeApprove(farmMaster, amount);

        IFarmMaster(farmMaster).deposit(pid, lpToken, amount);
    }

    // withdraw lp from farm pool
    function withdrawFromFarm(
        address farmMaster,
        uint256 pid,
        IERC20 lpToken,
        uint256 amount
    ) external onlyCore {
        require(Address.isContract(farmMaster), "ERR_NOT_CONTRACT");

        IFarmMaster(farmMaster).withdraw(pid, lpToken, amount);
    }
}

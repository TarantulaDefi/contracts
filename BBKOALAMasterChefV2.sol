// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

//  .----------------.  .----------------.  .----------------.  .----------------.  .----------------. 
// | .--------------. || .--------------. || .--------------. || .--------------. || .--------------. |
// | |  ___  ____   | || |     ____     | || |      __      | || |   _____      | || |      __      | |
// | | |_  ||_  _|  | || |   .'    `.   | || |     /  \     | || |  |_   _|     | || |     /  \     | |
// | |   | |_/ /    | || |  /  .--.  \  | || |    / /\ \    | || |    | |       | || |    / /\ \    | |
// | |   |  __'.    | || |  | |    | |  | || |   / ____ \   | || |    | |   _   | || |   / ____ \   | |
// | |  _| |  \ \_  | || |  \  `--'  /  | || | _/ /    \ \_ | || |   _| |__/ |  | || | _/ /    \ \_ | |
// | | |____||____| | || |   `.____.'   | || ||____|  |____|| || |  |________|  | || ||____|  |____|| |
// | |              | || |              | || |              | || |              | || |              | |
// | '--------------' || '--------------' || '--------------' || '--------------' || '--------------' |
// '----------------'  '----------------'  '----------------'  '----------------'  '----------------' 

import "./SafeMath.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./BBTARANTULAToken.sol";

// MasterChefV2 is the master of BabyTarantulas. He can make BabyTarantulas and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once BBTARANTULA is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BBTARANTULAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBabyTarantulasPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBabyTarantulasPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. BBTARANTULAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that BBTARANTULAs distribution occurs.
        uint256 accBabyTarantulasPerShare;   // Accumulated BBTARANTULAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The BBTARANTULA TOKEN!
    BabyTarantulaToken public babytarantula;
    // Dev address.
    address public devaddr;
    // BBTARANTULA tokens created per block.
    uint256 public babytarantulaPerBlock;
    // Bonus muliplier for early babytarantula makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BBTARANTULA mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    constructor(
        BabyTarantulaToken _babytarantula,
        address _devaddr,
        address _feeAddress,
        uint256 _babytarantulaPerBlock,
        uint256 _startBlock
    ) public {
        babytarantula = _babytarantula;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        babytarantulaPerBlock = _babytarantulaPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accBabyTarantulaPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update the given pool's BBTARANTULA allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending BBTARANTULAs on frontend.
    function pendingBabyTarantula(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBabyTarantulaPerShare = pool.accBabyTarantulaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 babytarantulaReward = multiplier.mul(babytarantulaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBabyTarantulaPerShare = accBabyTarantulaPerShare.add(babytarantulaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accBabyTarantulaPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 babytarantulaReward = multiplier.mul(babytarantulaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        babytarantula.mint(devaddr, babytarantulaReward.div(10));
        babytarantula.mint(address(this), babytarantulaReward);
        pool.accBabyTarantulaPerShare = pool.accBabyTarantulaPerShare.add(babytarantulaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for EGG allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accBabyTarantulaPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeBabyTarantulaTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accBabyTarantulaPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accBabyTarantulaPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeBabyTarantulaTransfer(msg.sender, pending);
        }
        if (pending > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBabyTarantulaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe babytarantula transfer function, just in case if rounding error causes pool to not have enough BBTARANTULAs.
    function safeBabyTarantulaTransfer(address _to, uint256 _amount) internal {
        uint256 babytarantulaBal = babytarantula.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > babytarantulaBal) {
            transferSuccess = babytarantula.transfer(_to, babytarantulaBal);
        } else {
            transferSuccess = babytarantula.transfer(_to, _amount);
        }
        require(transferSuccess, "safeEggTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _babytarantulaPerBlock) public onlyOwner {
        massUpdatePools();
        babytarantulaPerBlock = _babytarantulaPerBlock;
		emit UpdateEmissionRate(msg.sender, _babytarantulaPerBlock);
    }
}

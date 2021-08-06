// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "hardhat/console.sol";
import "./OpenZeppelin/contracts/token/ERC20/ERC20.sol";
import "./OpenZeppelin/contracts/utils/Address.sol";
import "./OpenZeppelin/contracts/utils/Context.sol";

/**
 * @dev ShieldLocker
 *
 * This contract allows anyone to lock any token. It also allows the user to specify vesting periods.
 * 
 * NOTE:
 * Using LockType.VESTING0 will lock your tokens till unlock time has expired.
 */
contract ShieldLocker is Context {

  address private _owner;

  enum LockType { VESTING0, VESTING2, VESTING4, VESTING5, VESTING10, VESTING20, VESTING25, VESTING50, VESTING100 }

  struct PoolInfo {
    ERC20 token;
    LockType lockType;
    uint256 lockTime;
    uint256 unlockTime;
    uint256 amount;
    uint256 originalAmount;
    uint256[] vestingSchedule;
    bool[] withdrawn;
    uint256[] withdrawalTimes;
    address owner;
  }
  uint256 private _pId = 0;
  PoolInfo[] public pools;

  mapping(address => uint256[]) private userPools;
  
  event PoolAdded(uint256 pId, address token, LockType lockType, uint256 unlockTime);
  event Withdraw(address sender, uint256 pId, uint256 amount, uint256 timestamp);

  modifier onlyOwner() {
    require(_owner == _msgSender(), "ShieldLocker: caller is not the owner.");
    _;
  }

  constructor (address owner) {
    _owner = owner;
  }

  function createPool(ERC20 token, LockType lockType, uint256 unlockTimeInSeconds, uint256 amount) public {
    require(amount > 0, "ShieldLocker: amount mus tbe greater than zero.");

    uint256 lockTime = block.timestamp;
    uint256 unlockTime = lockTime + (unlockTimeInSeconds - lockTime);

    require(unlockTime > block.timestamp, "ShieldLocker: unlock time should be greater than current block time.");

    uint256 pId = _pId++;
    uint256 n = getNumberOfVestingPeriods(lockType);

    userPools[_msgSender()].push(pId);
    pools.push(PoolInfo(
      token,
      lockType, 
      lockTime, 
      unlockTime, 
      amount,
      amount,
      generateVestingSchedule(
        lockTime, 
        unlockTime, 
        lockType
      ),
      new bool[](n),
      new uint256[](n),
      _msgSender()
    ));

    // transfer amount -- must be pre-approved by user
    token.transferFrom(_msgSender(), address(this), amount);

    emit PoolAdded(pId, address(token), lockType, unlockTime);
  }

  /**
   * @dev Get the number of vesting periods based on specified lock type.
   */
  function getNumberOfVestingPeriods(LockType lockType) private pure returns (uint256) {
    return lockType == LockType.VESTING0 ? 1
    : lockType == LockType.VESTING2 ? 2 
    : lockType == LockType.VESTING4 ? 4
    : lockType == LockType.VESTING5 ? 5
    : lockType == LockType.VESTING10 ? 10
    : lockType == LockType.VESTING20 ? 20
    : lockType == LockType.VESTING25 ? 25
    : lockType == LockType.VESTING50 ? 50
    : lockType == LockType.VESTING100 ? 100 : 1;
  }

  /**
   * @dev Generate vesting periods.
   * @return A uint256 array of timestamps representing the vesting periods.
   */
  function generateVestingSchedule(uint256 lockTime, uint256 unlockTime, LockType lockType) private pure returns(uint256[] memory) {
    uint256 n = getNumberOfVestingPeriods(lockType);
    uint256[] memory vestingSchedule = new uint256[](n);
    uint256 timeLeft = unlockTime - lockTime;
    uint256 period = timeLeft / n;

    // console.log("N", n);
    // console.log("Lock", lockTime);
    // console.log("Unlock", unlockTime);
    // console.log("Left", timeLeft);
    // console.log("Period", period);

    uint256 index = 0;
    do {
      vestingSchedule[index] = lockTime + period * (index + 1);
    } while(++index < n);

    return vestingSchedule;
  }

  /**
   * @dev Withdraw founds of the specified vesting period in the specified pool.
   *
   * Requirements
   * 
   * - Block timestamp should be greater than specified vesting period.
   * - Specified vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the pool owner.
   * - Pool's balance should be greater than zero.
   */
  function withdraw(uint256 pId, uint256 vestingPeriodId) public {
    require(block.timestamp > pools[pId].vestingSchedule[vestingPeriodId], "ShieldLocker: vesting period has not expired.");
    require(!pools[pId].withdrawn[vestingPeriodId], "ShiedLocker: vesting period already done.");
    require(_msgSender() == pools[pId].owner, "ShieldLocker: you are not the owner of this pool.");
    require(pools[pId].amount > 0, "ShieldLocker: insufficient balance.");
    
    // flag as withdrawn
    pools[pId].withdrawn[vestingPeriodId] = true;
    // set withdrawal timestamp
    pools[pId].withdrawalTimes[vestingPeriodId] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = 0;
    if(vestingPeriodId == pools[pId].vestingSchedule.length - 1)
      amountToBeTransfered = pools[pId].amount;
    else
      amountToBeTransfered = pools[pId].originalAmount / pools[pId].vestingSchedule.length;
    
    // update pool amount
    pools[pId].amount -= amountToBeTransfered;
    
    // transfer funds
    pools[pId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), pId, amountToBeTransfered, pools[pId].withdrawalTimes[vestingPeriodId]);
  }

  /**
   * @dev Withdraw all pool funds.
   *
   * Requirements
   * 
   * - Block timestamp should be greater than last vesting period.
   * - Last vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the pool owner.
   * - Pool's balance should be greater than zero.
   */
  function withdrawAll(uint256 pId) public {
    require(block.timestamp > pools[pId].vestingSchedule[pools[pId].vestingSchedule.length - 1], "ShieldLocker: vesting period has not expired.");
    require(!pools[pId].withdrawn[pools[pId].withdrawn.length - 1], "ShiedLocker: vesting period already done.");
    require(_msgSender() == pools[pId].owner, "ShieldLocker: you are not the owner of this pool.");
    require(pools[pId].amount > 0, "ShieldLocker: insufficient balance.");

    // flag as widthdrawn
    pools[pId].withdrawn[pools[pId].withdrawn.length - 1] = true;
    // set widthdrawal timestamp
    pools[pId].withdrawalTimes[pools[pId].withdrawalTimes.length - 1] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = pools[pId].amount;
    
    // update pool amount
    pools[pId].amount = 0;

    // transfer funds
    pools[pId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), pId, amountToBeTransfered, pools[pId].withdrawalTimes[pools[pId].withdrawalTimes.length - 1]);
  }

  function fetchPage(uint256 pageIndex, uint256 pageSize) public view returns(uint256[] memory) {
    if(pageSize > pools.length)
      pageSize = pool.length;

    uint256[] items = new uint256[](pageSize);
    uint256 totalPages = pools.length / pageSize;
    if(pageIndex > totalPages) {
      pageIndex = totalPages;
    }

    uint256 startIndex = pageIndex * pageSize;
    for(uint pId = startIndex; pId < startIndex + pageSize && pId < pools.length; pId++) {
      items[pId] = pId;
    }

    return items;
  }

  function getUserPools(address user) public view returns(uint256[] memory) {
    return userPools[user];
  }

  function getVestingScheduleDetails(uint256 pId) public view 
  returns(
    uint256[] memory vestingSchedule, 
    bool[] memory withdrawn, 
    uint256[] memory withdrawalTimes
  ) {
    vestingSchedule = pools[pId].vestingSchedule;
    withdrawn = pools[pId].withdrawn;
    withdrawalTimes = pools[pId].withdrawalTimes;
  }

  function allowToExecuteWithdraw(uint256 pId, uint256 vestingPeriodId) public onlyOwner {
    pools[pId].vestingSchedule[vestingPeriodId] = block.timestamp-1;
  }

  
  function allowToExecuteWithdrawAll(uint256 pId) public onlyOwner {
    pools[pId].vestingSchedule[pools[pId].vestingSchedule.length - 1] = block.timestamp-1;
  }

}
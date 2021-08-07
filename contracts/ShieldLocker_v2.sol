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
contract ShieldLocker_v2 is Context {

  address private _owner;

  enum VestingType { VESTING0, VESTING2, VESTING4, VESTING5, VESTING10, VESTING20, VESTING25, VESTING50, VESTING100 }

  struct PoolInfo {
    ERC20 token;
    VestingType vestingType;
    uint256 lockTime;
    uint256 unlockTime;
    uint256 amount;
    uint256 originalAmount;
    address owner;
  }
  uint256 private _pId = 0;
  PoolInfo[] public pools;

  // pool => vesting period => true/false
  mapping(uint256 => mapping(uint256 => bool)) public withdrawn;
  // pool => veting period => timestamp
  mapping(uint256 => mapping(uint256 => uint256)) public withdrawalTimes;

  // address => pools
  mapping(address => uint256[]) private userPools;
  
  event PoolAdded(uint256 pId, address token, VestingType vestingType, uint256 unlockTime);
  event Withdraw(address sender, uint256 pId, uint256 amount, uint256 timestamp);
  event EmergencyWithdraw(address sender, uint256 pId, uint256 amount, uint256[] vestingPeriodIds);

  modifier onlyOwner() {
    require(_owner == _msgSender(), "ShieldLocker: caller is not the owner.");
    _;
  }

  constructor (address owner) {
    _owner = owner;
  }

  function createPool(ERC20 token, VestingType vestingType, uint256 unlockTimeInSeconds, uint256 amount) public {
    require(amount > 0, "ShieldLocker: amount mus tbe greater than zero.");

    uint256 lockTime = block.timestamp;
    uint256 unlockTime = lockTime + (unlockTimeInSeconds - lockTime);

    require(unlockTime > block.timestamp, "ShieldLocker: unlock time should be greater than current block time.");

    uint256 pId = _pId++;

    userPools[_msgSender()].push(pId);
    pools.push(PoolInfo(
      token,
      vestingType, 
      lockTime, 
      unlockTime, 
      amount,
      amount,
      _msgSender()
    ));

    // transfer amount -- must be pre-approved by user
    token.transferFrom(_msgSender(), address(this), amount);

    emit PoolAdded(pId, address(token), vestingType, unlockTime);
  }

  /**
   * @dev Get the number of vesting periods based on specified lock type.
   */
  function getNumberOfVestingPeriods(VestingType vestingType) public pure returns (uint256) {
    return vestingType == VestingType.VESTING0 ? 1  // 100%
    : vestingType == VestingType.VESTING2 ? 2       // 50%
    : vestingType == VestingType.VESTING4 ? 4       // 25%
    : vestingType == VestingType.VESTING5 ? 5       // 20%
    : vestingType == VestingType.VESTING10 ? 10     // 10%
    : vestingType == VestingType.VESTING20 ? 20 	  // 5%
    : vestingType == VestingType.VESTING25 ? 25     // 4%
    : vestingType == VestingType.VESTING50 ? 50     // 2%
    : vestingType == VestingType.VESTING100 ? 100   // 1%
    : 1;                                            // 100%
  }

  /**
   * @dev Withdraw founds of the specified vesting period in the specified pool.
   *
   * Requirements
   * 
   * - Pool index should be inside array range.
   * - Vesting period should be inside n range.
   * - Specified vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the pool owner.
   * - Pool's balance should be greater than zero.
   * - Block's timestamp should be greater than specified vesting period.
   */
  function withdraw(uint256 pId, uint256 vestingPeriodId) public {
    uint256 n = getNumberOfVestingPeriods(pools[pId].vestingType);

    require(pId >= 0 && pId < pools.length, "ShieldLocker: invalid pool index.");
    require(vestingPeriodId >= 0 && vestingPeriodId < n, "ShieldLocker: invalid vesting period.");
    require(!withdrawn[pId][vestingPeriodId], "ShieldLocker: vesting period already done.");
    require(_msgSender() == pools[pId].owner, "ShieldLocker: you are not the owner of this pool.");
    require(pools[pId].amount > 0, "ShieldLocker: insufficient balance.");

    uint256 timeDiff = pools[pId].unlockTime - pools[pId].lockTime;
    uint256 vestingPeriod = pools[pId].lockTime + timeDiff / n * (vestingPeriodId + 1);

    require(block.timestamp > vestingPeriod, "ShieldLocker: vesting period has not expired.");

    // flag as withdrawn
    withdrawn[pId][vestingPeriodId] = true;
    // set withdrawal timestamp
    withdrawalTimes[pId][vestingPeriodId] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = 0;
    if(vestingPeriodId == n - 1)
      amountToBeTransfered = pools[pId].amount;
    else
      amountToBeTransfered = pools[pId].originalAmount / n;
    
    // update pool's amount
    pools[pId].amount -= amountToBeTransfered;
    
    // transfer funds
    pools[pId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), pId, amountToBeTransfered, withdrawalTimes[pId][vestingPeriodId]);
  }

  /**
   * @dev Withdraw all pool funds.
   *
   * Requirements
   * 
   * - Pool index should be inside array range.
   * - Last vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the pool owner.
   * - Pool's balance should be greater than zero.
   * - Block's timestamp should be greater than unlock time.
   */
  function withdrawAll(uint256 pId) public {
    uint256 n = getNumberOfVestingPeriods(pools[pId].vestingType);

    require(pId >= 0 && pId < pools.length, "ShieldLocker: invalid pool index.");
    require(!withdrawn[pId][n - 1], "ShieldLocker: vesting period already done.");
    require(_msgSender() == pools[pId].owner, "ShieldLocker: you are not the owner of this pool.");
    require(pools[pId].amount > 0, "ShieldLocker: insufficient balance.");

    require(block.timestamp > pools[pId].unlockTime, "ShieldLocker: vesting period has not expired.");

    // flag as widthdrawn
    withdrawn[pId][n - 1] = true;
    // set widthdrawal timestamp
    withdrawalTimes[pId][n - 1] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = pools[pId].amount;
    
    // update pool's amount
    pools[pId].amount = 0;

    // transfer funds
    pools[pId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), pId, amountToBeTransfered, withdrawalTimes[pId][n - 1]);
  }

  function fetchPage(uint256 pageIndex, uint256 pageSize) public view returns(uint256[] memory) {
    if(pageSize > pools.length)
      pageSize = pools.length;

    uint256[] memory items = new uint256[](pageSize);
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

  /**
   * @dev Allows admin to withdraw N vesting periods as requested by pool's owner.
   * This function ignores pool's vesting schedule.
   */
  function adminWithdraw(uint256 pId, uint256[] memory vestingPeriodIds) public onlyOwner {
    require(pId >= 0 && pId < pools.length, "ShieldLocker: invalid pool index.");
    require(pools[pId].amount > 0, "ShieldLocker: insufficient balance.");

    uint256 n = getNumberOfVestingPeriods(pools[pId].vestingType);

    require(vestingPeriodIds.length > 0 && vestingPeriodIds.length <= n, "ShieldLocker: invalid number of vesting periods.");

    for(uint56 i = 0; i < vestingPeriodIds.length; i++) {
      require(!withdrawn[pId][vestingPeriodIds[i]], "ShieldLocker: vesting period already done.");
      withdrawn[pId][vestingPeriodIds[i]] = true;
      withdrawalTimes[pId][vestingPeriodIds[i]] = block.timestamp;
    }
    
    // determine how much should be transfered
    uint256 amountToBeTransfered = pools[pId].originalAmount / n * vestingPeriodIds.length;

    // update pool's amount
    pools[pId].amount -= amountToBeTransfered;

    // transfer funds
    pools[pId].token.transfer(pools[pId].owner, amountToBeTransfered);

    emit EmergencyWithdraw(_msgSender(), pId, amountToBeTransfered, vestingPeriodIds);
  }
}
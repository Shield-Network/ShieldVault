// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

//import "hardhat/console.sol";
import "./OpenZeppelin/contracts/token/ERC20/ERC20.sol";
import "./OpenZeppelin/contracts/utils/Address.sol";
import "./OpenZeppelin/contracts/utils/Context.sol";

/**
 * @dev ShieldLocker
 *
 * This contract allows anyone to lock any token. It also allows the user to specify vesting periods.
 * 
 * NOTE:
 * Using VestingType.VESTING0 will lock your tokens till unlock time has expired.
 */
contract ShieldLocker_v2 is Context {

  address private _owner;

  enum VestingType { VESTING0, VESTING2, VESTING4, VESTING5, VESTING10, VESTING20, VESTING25, VESTING50, VESTING100 }

  struct LockerInfo {
    ERC20 token;
    VestingType vestingType;
    uint256 lockTime;
    uint256 unlockTime;
    uint256 amount;
    uint256 originalAmount;
    address owner;
  }
  uint256 private _lockerId = 0;
  LockerInfo[] public lockers;

  // locker => vesting period => true/false
  mapping(uint256 => mapping(uint256 => bool)) public withdrawn;
  // locker => veting period => timestamp
  mapping(uint256 => mapping(uint256 => uint256)) public withdrawalTimes;

  // address => lockers
  mapping(address => uint256[]) private userLockers;
  
  event LockerAdded(uint256 lockerId, address token, VestingType vestingType, uint256 unlockTime);
  event Withdraw(address sender, uint256 lockerId, uint256 amount, uint256 timestamp);
  event AdminWithdraw(address sender, uint256 lockerId, uint256 amount, uint256[] vestingPeriodIds);

  modifier onlyOwner() {
    require(_owner == _msgSender(), "ShieldLocker: caller is not the owner.");
    _;
  }

  constructor (address owner) {
    _owner = owner;
  }

  function createLocker(ERC20 token, VestingType vestingType, uint256 unlockTimeInSeconds, uint256 amount) public {
    require(amount > 0, "ShieldLocker: amount mus tbe greater than zero.");

    uint256 lockTime = block.timestamp;
    uint256 unlockTime = lockTime + (unlockTimeInSeconds - lockTime);

    require(unlockTime > block.timestamp, "ShieldLocker: unlock time should be greater than current block time.");

    uint256 lockerId = _lockerId++;

    userLockers[_msgSender()].push(lockerId);
    lockers.push(LockerInfo(
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

    emit LockerAdded(lockerId, address(token), vestingType, unlockTime);
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
   * @dev Withdraw founds of the specified vesting period in the specified locker.
   *
   * Requirements
   * 
   * - Locker index should be inside array range.
   * - Vesting period should be inside n range.
   * - Specified vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the locker owner.
   * - Locker's balance should be greater than zero.
   * - Block's timestamp should be greater than specified vesting period.
   */
  function withdraw(uint256 lockerId, uint256 vestingPeriodId) public {
    uint256 n = getNumberOfVestingPeriods(lockers[lockerId].vestingType);

    require(lockerId >= 0 && lockerId < lockers.length, "ShieldLocker: invalid locker index.");
    require(vestingPeriodId >= 0 && vestingPeriodId < n, "ShieldLocker: invalid vesting period.");
    require(!withdrawn[lockerId][vestingPeriodId], "ShieldLocker: vesting period already done.");
    require(_msgSender() == lockers[lockerId].owner, "ShieldLocker: you are not the owner of this locker.");
    require(lockers[lockerId].amount > 0, "ShieldLocker: insufficient balance.");

    uint256 timeDiff = lockers[lockerId].unlockTime - lockers[lockerId].lockTime;
    uint256 vestingPeriod = lockers[lockerId].lockTime + timeDiff / n * (vestingPeriodId + 1);

    require(block.timestamp > vestingPeriod, "ShieldLocker: vesting period has not expired.");

    // flag as withdrawn
    withdrawn[lockerId][vestingPeriodId] = true;
    // set withdrawal timestamp
    withdrawalTimes[lockerId][vestingPeriodId] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = 0;
    if(vestingPeriodId == n - 1)
      amountToBeTransfered = lockers[lockerId].amount;
    else
      amountToBeTransfered = lockers[lockerId].originalAmount / n;
    
    // update locker's amount
    lockers[lockerId].amount -= amountToBeTransfered;
    
    // transfer funds
    lockers[lockerId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), lockerId, amountToBeTransfered, withdrawalTimes[lockerId][vestingPeriodId]);
  }

  /**
   * @dev Withdraw all locker funds.
   *
   * Requirements
   * 
   * - Locker index should be inside array range.
   * - Last vesting period should not be flagged as withdrawn.
   * - _msgSender() should return the address of the locker owner.
   * - Lockers's balance should be greater than zero.
   * - Block's timestamp should be greater than unlock time.
   */
  function withdrawAll(uint256 lockerId) public {
    uint256 n = getNumberOfVestingPeriods(lockers[lockerId].vestingType);

    require(lockerId >= 0 && lockerId < lockers.length, "ShieldLocker: invalid locker index.");
    require(!withdrawn[lockerId][n - 1], "ShieldLocker: vesting period already done.");
    require(_msgSender() == lockers[lockerId].owner, "ShieldLocker: you are not the owner of this locker.");
    require(lockers[lockerId].amount > 0, "ShieldLocker: insufficient balance.");

    require(block.timestamp > lockers[lockerId].unlockTime, "ShieldLocker: vesting period has not expired.");

    // flag as widthdrawn
    withdrawn[lockerId][n - 1] = true;
    // set widthdrawal timestamp
    withdrawalTimes[lockerId][n - 1] = block.timestamp;

    // determine how much should be transfered
    uint256 amountToBeTransfered = lockers[lockerId].amount;
    
    // update locker's amount
    lockers[lockerId].amount = 0;

    // transfer funds
    lockers[lockerId].token.transfer(_msgSender(), amountToBeTransfered);

    emit Withdraw(_msgSender(), lockerId, amountToBeTransfered, withdrawalTimes[lockerId][n - 1]);
  }

  function fetchPage(uint256 pageIndex, uint256 pageSize) public view returns(uint256[] memory) {
    if(pageSize > lockers.length)
      pageSize = lockers.length;

    uint256[] memory items = new uint256[](pageSize);
    uint256 totalPages = lockers.length / pageSize;
    if(pageIndex > totalPages) {
      pageIndex = totalPages;
    }

    uint256 startIndex = pageIndex * pageSize;
    for(uint lockerId = startIndex; lockerId < startIndex + pageSize && lockerId < lockers.length; lockerId++) {
      items[lockerId] = lockerId;
    }

    return items;
  }

  function getUserLockers(address user) public view returns(uint256[] memory) {
    return userLockers[user];
  }

  /**
   * @dev Allows admin to withdraw N vesting periods as requested by locker's owner.
   * This function ignores locker's vesting schedule.
   */
  function adminWithdraw(uint256 lockerId, uint256[] memory vestingPeriodIds) public onlyOwner {
    require(lockerId >= 0 && lockerId < lockers.length, "ShieldLocker: invalid locker index.");
    require(lockers[lockerId].amount > 0, "ShieldLocker: insufficient balance.");

    uint256 n = getNumberOfVestingPeriods(lockers[lockerId].vestingType);

    require(vestingPeriodIds.length > 0 && vestingPeriodIds.length <= n, "ShieldLocker: invalid number of vesting periods.");

    for(uint56 i = 0; i < vestingPeriodIds.length; i++) {
      require(!withdrawn[lockerId][vestingPeriodIds[i]], "ShieldLocker: vesting period already done.");
      withdrawn[lockerId][vestingPeriodIds[i]] = true;
      withdrawalTimes[lockerId][vestingPeriodIds[i]] = block.timestamp;
    }
    
    // determine how much should be transfered
    uint256 amountToBeTransfered = lockers[lockerId].originalAmount / n * vestingPeriodIds.length;

    // update locker's amount
    lockers[lockerId].amount -= amountToBeTransfered;

    // transfer funds
    lockers[lockerId].token.transfer(lockers[lockerId].owner, amountToBeTransfered);

    emit AdminWithdraw(_msgSender(), lockerId, amountToBeTransfered, vestingPeriodIds);
  }
}
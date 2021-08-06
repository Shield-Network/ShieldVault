const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const web3 = require("web3-utils");

describe("ShiedLocker.sol: Unit Tests", function () {
  let ShieldLocker,
    locker,
    _token,
    owner,
    user1,
    _unlockTime = new Date("2021-12-01 00:00:00").getTime() / 1000;

  it("Deployment should assign 1 owners.", async () => {
    [owner, user1] = await ethers.getSigners();

    ShieldLocker = await ethers.getContractFactory("ShieldLocker");
    const DummyToken = await ethers.getContractFactory("DummyToken");

    locker = await ShieldLocker.deploy(owner.address);
    _token = await DummyToken.deploy(1000000);

    var balance = await _token.balanceOf(owner.address);
    expect(balance).to.be.equal(1000000, "DummyToken: invalid initial supply");
  });
  it("Transfer tokens to user1.", async () => {
    await _token.connect(owner).transfer(user1.address, 500001);

    var balance = await _token.balanceOf(user1.address);
    expect(balance).to.be.equal(500001, "DummyToken: invalid balance.");
  });
  it("Approve locker contract to transfer tokens.", async () => {
    var balance = await _token.balanceOf(user1.address); 
    await _token.connect(user1).approve(locker.address, balance);
    var allowance = await _token.allowance(user1.address, locker.address);
    expect(allowance).to.be.equal(500001, "DummyToken: wrong allowance.");
  });
  it("Create a pool.", async () => {
    var allowance = await _token.allowance(user1.address, locker.address);
    expect(await locker.connect(user1).createPool(_token.address, 8, _unlockTime, allowance))
    .to.emit(locker, "PoolAdded");
  });
  it("Get pool info.", async () => {
    var [token, lockType, unlockTime, amount, vestingPeriods, withdrawn] = await locker.getPoolInfo(0);

    // vestingPeriods.forEach((period, index) => {
    //   console.log("Period", index, "Date", new Date(period * 1000));
    // })
    // console.log(withdrawed);
    expect(token).to.be.equal(_token.address, "Invalid token address.");
    expect(lockType).to.be.equal(8, "Invalid lock type.");
    expect(unlockTime.toNumber()).to.be.equal(_unlockTime, "Inalid unlock time.");
    expect(amount).to.be.equal(500001, "Invalid amount.");
  });
  it("Should not allow to withdrwal all.", async () => {
    await expect(locker.connect(user1).withdrawAll(0))
    .to.be.revertedWith("ShieldLocker: vesting period has not expired.");
  });
  it("Should allow to withdraw.", async () => {
    var [token, lockType, unlockTime, amount, vestingPeriods, withdrawn] = await locker.getPoolInfo(0);

    // withdraw 1
    await locker.allowToExecuteWithdraw(0, 0);
    expect(await locker.connect(user1).withdraw(0, 0))
    .to.emit(locker, "Withdraw");

    var balance = await _token.balanceOf(user1.address);
    var expectedBalance = Math.floor(amount / vestingPeriods.length);

    expect(balance).to.be.equal(expectedBalance, "1: Wrong user1 balance.");

    // withdraw 2
    await locker.allowToExecuteWithdraw(0, 1);
    expect(await locker.connect(user1).withdraw(0, 1))
    .to.emit(locker, "Withdraw");

    balance = await _token.balanceOf(user1.address);
    expectedBalance = Math.floor(amount / vestingPeriods.length) * 2;

    expect(balance).to.be.equal(expectedBalance, "2: Wrong user1 balance.");

    // withdraw all left
    await locker.allowToExecuteWithdrawAll(0);
    expect(await locker.connect(user1).withdrawAll(0))
    .to.emit(locker, "Withdraw");

    var lockerBalance = await _token.balanceOf(locker.address);
    balance = await _token.balanceOf(user1.address);
    expectedBalance = amount;

    expect(lockerBalance).to.be.equal(0, "Wrong locker balance.");
    expect(balance).to.be.equal(expectedBalance, "3: Wrong user1 balance.");
  });
  it("Should not allow withdraw if already withdrawn.", async () => {
    await expect(locker.connect(user1).withdraw(0, 1))
    .to.be.revertedWith("ShiedLocker: vesting period already done.");
  });
  it("Should not allow withdraw all.", async () => {
    await expect(locker.connect(user1).withdrawAll(0))
    .to.be.revertedWith("ShiedLocker: vesting period already done.");
  });
});

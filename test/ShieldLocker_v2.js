const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const { hexStripZeros } = require("ethers/lib/utils");
const { ethers, network } = require("hardhat");
const web3 = require("web3-utils");

describe("ShiedLocker.sol: Unit Tests", function () {
  let ShieldLocker,
    locker,
    _token,
    owner,
    user1,
    _unlockTime = new Date("2021-08-10 00:00:00").getTime() / 1000,
    pId = 0;

  it("Deployment should assign 1 owners.", async () => {
    [owner, user1] = await ethers.getSigners();

    ShieldLocker = await ethers.getContractFactory("ShieldLocker_v2");
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
    var { token, vestingType, unlockTime, amount } = await locker.pools(pId);

    // vestingPeriods.forEach((period, index) => {
    //   console.log("Period", index, "Date", new Date(period * 1000));
    // })
    // console.log(withdrawed);
    expect(token).to.be.equal(_token.address, "Invalid token address.");
    expect(vestingType).to.be.equal(8, "Invalid vesting type.");
    expect(unlockTime.toNumber()).to.be.equal(_unlockTime, "Inalid unlock time.");
    expect(amount).to.be.equal(500001, "Invalid amount.");
  });
  it("Should not allow to withdrwal all.", async () => {
    await expect(locker.connect(user1).withdrawAll(pId))
    .to.be.revertedWith("ShieldLocker: vesting period has not expired.");
  });
  it("Should allow to withdraw after 45 minutes.", async () => {
    var { vestingType, amount } = await locker.pools(pId);

    var n = await locker.getNumberOfVestingPeriods(vestingType);

    // increase time by 45 minutes to allow first vesting
    await network.provider.request({
      method: "evm_increaseTime",
      params: [60 * 45],
    })

    // withdraw 1
    expect(await locker.connect(user1).withdraw(pId, 0))
    .to.emit(locker, "Withdraw");

    var balance = await _token.balanceOf(user1.address);
    var expectedBalance = Math.floor(amount / n.toNumber());

    expect(balance).to.be.equal(expectedBalance, "1: Wrong user1 balance.");
  });
  it("Should not allow withdraw if already withdrawn.", async () => {
    await expect(locker.connect(user1).withdraw(pId, 0))
    .to.be.revertedWith("ShieldLocker: vesting period already done.");
    expect(await locker.withdrawn(pId, 0)).to.be.equal(true, "ShieldLocker: invalid flag.");
  });
  it("Should not allow withdraw all.", async () => {
    await expect(locker.connect(user1).withdrawAll(pId))
    .to.be.revertedWith("ShieldLocker: vesting period has not expired.");
  });
  it("Get user pools", async () => {
    var pools = await locker.getUserPools(user1.address);
    expect(pools.length).to.be.equal(1, "Shieldlocker: invalid pool length.");
    expect(pools[0]).to.be.equal(pId, "ShieldLocker: wrong pool found.");
  })
});

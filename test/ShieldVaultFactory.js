const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const web3 = require("web3-utils");

describe("ShieldVaultFactory.sol: Unit Tests", function () {
  let shield, p1, p2, factory, vault, token, proxy, proxyClone;

  it("Get accounts", async () => {
    [shield, p1, p2] = await ethers.getSigners();
  });

  it("Deploy DummyToken", async () => {
    const DummyToken = await ethers.getContractFactory("DummyToken");
    token = await DummyToken.deploy(BigNumber.from(web3.toWei("1000000")));

    expect(token.address).to.not.equal(0, "zero address");

    const totalSupply = await token.totalSupply();
    expect(web3.fromWei(totalSupply.toString())).to.be.equal(
      "1000000",
      "wrong supply"
    );
  });

  it("Transfer DummyToken to p1", async () => {
    token.transfer(p1.address, BigNumber.from(web3.toWei("500")));

    const balance = await token.balanceOf(p1.address);
    expect(web3.fromWei(balance.toString())).to.be.equal(
      "500",
      "wrong balance"
    );
  });

  it("Deploy vault implementation", async () => {
    const ShieldVault = await ethers.getContractFactory("ShieldVault");
    vault = await ShieldVault.deploy();

    console.log("Vault implementation address", vault.address);
    expect(vault.address).to.not.equal(0, "Unknown address");
  });

  it("Deploy factory", async () => {
    const ShieldVaultFactory = await ethers.getContractFactory(
      "ShieldVaultFactory"
    );
    factory = await ShieldVaultFactory.deploy(shield.address, vault.address);

    console.log("Factory address", factory.address);
    expect(await factory.getOwner()).to.be.equal(shield.address);
  });

  it("Add pool", async () => {
    expect(await factory.addToken("DummyToken", token.address)).to.emit(
      factory,
      "TokenAdded"
    );
  });

  it("Create vault for p1", async () => {
    // create vault
    expect(
      await factory.connect(p1).createVault(0, [shield.address, p1.address], 1)
    ).to.emit(factory, "VaultCreated");

    const events = await factory.queryFilter(
      factory.filters.VaultCreated(),
      "latest"
    );
    proxy = events[0].args[0];

    console.log("Proxy address", proxy);
    expect(proxy).to.not.be.equal(vault.address, "wrong address");

    // approve vault to use transferFrom
    token.connect(p1).approve(proxy, BigNumber.from(web3.toWei("500")));
  });

  it("Deposit token into vault", async () => {
    const ShieldVault = await ethers.getContractFactory("ShieldVault");
    // load proxy clone
    proxyClone = await ShieldVault.attach(proxy);

    // deposit - execute transferFrom
    expect(
      await proxyClone.connect(p1).deposit(BigNumber.from(web3.toWei("500")))
    ).to.emit(proxyClone, "TokenDeposit");

    // validate p1 balance
    expect(await token.balanceOf(p1.address)).to.be.equal(0, "wrong p1 token blanace");

    // validate token balance
    const balance = await proxyClone.connect(p1).getTokenBalance();
    expect(web3.fromWei(balance.toString())).to.be.equal(
      "500",
      "wrong vault token balance"
    );
  });

  it("Get p1 vaults", async () => {
    const vaultIndexes = await factory.getVaults(p1.address);
    expect(vaultIndexes.length).to.be.equal(1, "wrong length");

    const vaultAddress = await factory.getVaultAddress(vaultIndexes[0]);
    expect(vaultAddress).to.be.equal(proxy, "wrong address");
  })

  it("Token withdrawal", async () => {
    const ShieldVault = await ethers.getContractFactory("ShieldVault");
    // load proxy clone
    proxyClone = await ShieldVault.attach(proxy);

    // submit transaction as p1
    expect(await proxyClone.connect(p1).requestTokenWithdrawal(p1.address, BigNumber.from(web3.toWei("500")), "tx description"))
      .to.emit(proxyClone, "SubmitTransaction");

    // try to execute transaction without confirmations
    expect(proxyClone.executeTransaction(0)).to.be.revertedWith("cannot execute tx");

    // try to confirm transaction as p1
    expect(proxyClone.connect(p1).confirmTransaction(0)).to.be.revertedWith("You cannot confirm this transaction.");

    // try to confirm transaction as p2
    expect(proxyClone.connect(p2).confirmTransaction(0)).to.be.revertedWith("not owner");

    // confirm transaction as shield
    expect(await proxyClone.confirmTransaction(0)).to.emit(proxyClone, "ConfirmTransaction");

    // execute transaction as p1
    expect(await proxyClone.connect(p1).executeTransaction(0)).to.emit(proxyClone, "ExecuteTransaction");

    // validate token balance
    const proxyBalance = await token.balanceOf(proxyClone.address);
    expect(web3.fromWei(proxyBalance.toString())).to.be.equal("0", "wrong vault token balance");

    // validate p1 token balance
    const p1TokenBalance = await token.balanceOf(p1.address);
    expect(web3.fromWei(p1TokenBalance.toString())).to.be.equal("500", "wrong p1 token balance");
  });
});

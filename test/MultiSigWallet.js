const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const web3 = require("web3-utils");

describe("MultiSigWallet.sol: Unit Tests", function () {
  let shield,
    xpj,
    wallet,
    walletBalanceWei,
    walletBalance,
    xpjBalanceWei,
    xpjBalance;

  it("Deployment should assign 2 owners.", async () => {
    [shield, xpj] = await ethers.getSigners();

    const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");

    wallet = await MultiSigWallet.deploy([shield.address, xpj.address], 1);

    const owners = await wallet.getOwners();
    expect(owners.length).to.be.equal(2, "Invalid number of owners.");
  });

  //Some comment
  it("Tranfer 50 ETH to wallet.", async () => {
    // transfer eth to wallet
    const result = await xpj.sendTransaction({
      to: wallet.address,
      value: BigNumber.from(web3.toWei("50")),
    });

    walletBalanceWei = await wallet.getBalance();
    xpjBalanceWei = await xpj.getBalance();

    walletBalance = web3.fromWei(walletBalanceWei.toString());
    xpjBalance = web3.fromWei(xpjBalanceWei.toString());

    console.log("Wallet balance: ", walletBalance);
    console.log("XPJ balance: ", xpjBalance);

    expect(walletBalance).to.be.equal("50", "Invalid wallet balance.");
  });

  it("submitTransaction", async () => {
    await wallet
      .connect(xpj)
      .submitTransaction(xpj.address, BigNumber.from(web3.toWei("50")), 0x0);

    // validate that transaction has been created
    expect(await wallet.getTransactionCount()).to.be.equal(
      1,
      "Invalid number of transactions."
    );
  });

  it("Should allow transaction to be executed only after shield cofirmations.", async () => {
    // try to confirm transaction from the same address
    expect(wallet.connect(xpj).confirmTransaction(0)).to.be.revertedWith(
      "VM Exception while processing transaction: reverted with reason string 'You cannot confirm this transaction.'"
    );

    // transaction should not be confirmed yet
    expect(await wallet.isConfirmed(0, shield.address)).to.be.equal(
      false,
      "Transaction should not be confirmed yet."
    );

    // try to execute transaction without confirmations
    expect(wallet.connect(xpj).executeTransaction(0)).to.be.revertedWith(
      "cannot execute tx"
    );

    // confirm transaction using other owner address
    expect(await wallet.connect(shield).confirmTransaction(0))
      .to.emit(wallet, "ConfirmTransaction")
      .withArgs(shield.address, 0);

    expect(await wallet.isConfirmed(0, shield.address)).to.be.equal(
      true,
      "Transaction was not confirmed."
    );

    // show balances before executing transaction
    walletBalanceWei = await wallet.getBalance();
    xpjBalanceWei = await xpj.getBalance();

    walletBalance = web3.fromWei(walletBalanceWei.toString());
    xpjBalance = web3.fromWei(xpjBalanceWei.toString());

    console.log("Wallet balance before: ", walletBalance);
    console.log("XPJ balance before: ", xpjBalance);

    // execute transaction
    expect(await wallet.connect(xpj).executeTransaction(0))
      .to.emit(wallet, "ExecuteTransaction")
      .withArgs(xpj.address, 0);

    walletBalanceWei = await wallet.getBalance();
    xpjBalanceWei = await xpj.getBalance();

    walletBalance = web3.fromWei(walletBalanceWei.toString());
    xpjBalance = web3.fromWei(xpjBalanceWei.toString());

    console.log("Wallet balance after: ", walletBalance);
    console.log("XPJ balance after: ", xpjBalance);
  });
});

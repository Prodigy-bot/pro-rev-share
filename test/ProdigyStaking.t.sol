// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import "forge-std/Test.sol";
import { ProdigyBot, ERC20 } from "../src/ProdigyBot.sol";
import { ProdigyRevenueShare } from "../src/ProdigyRevenueShare.sol";
import { UniswapMock } from "./UniswapMock.sol";
import "forge-std/console.sol";

interface IRouter {
	function factory() external pure returns (address);
	function WETH() external pure returns (address);
	function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
	function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
	function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
	function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IFactory {
	function getPair(address tokenA, address tokenB) external view returns (address lpPair);
	function createPair(address tokenA, address tokenB) external returns (address lpPair);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract CannotReceiveEther {
	receive() external payable {
		revert();
	}

	fallback() external payable {
		revert();
	}
}

contract MockERC20 is ERC20 {
	constructor() {
		_mint(msg.sender, 1_000_000 ether);
	}

	function name() public pure override returns (string memory) {
		return "Testing";
	}

    function symbol() public pure override returns (string memory) {
		return "TEST";
	}
}

contract ProdigyStakingTest is Test {

	ProdigyBot private prodigy;
	ProdigyRevenueShare private rev;
	IRouter private _uniswapRouter;
	address[5] private _mockStakers;
	uint256 constant ROUNDING = 1;
	UniswapMock mock = new UniswapMock();

	event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

	function setUp() public {
		address router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
		vm.etch(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), mock.weth());
		vm.etch(address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f), mock.factory());
		vm.etch(router, mock.router());
		_uniswapRouter = IRouter(router);
		prodigy = new ProdigyBot(router);
		rev = new ProdigyRevenueShare(address(prodigy), router);
		rev.setIsOpen(true);
		rev.setDevReceiver(0x4077839b9A20D04daD8b0870b443E0F460A9AfD5);
	}

	function _launchToken() private {
		uint256 balance = prodigy.balanceOf(address(this));
		_uniswapRouter.addLiquidityETH{value: 4 ether}(address(prodigy), balance * 50 / 100, 0, 0, address(this), block.timestamp);
		address pair = IFactory(_uniswapRouter.factory()).getPair(_uniswapRouter.WETH(), address(prodigy));
		prodigy.release(pair);
		prodigy.setIsLimited(false);
		prodigy.setTaxExempt(address(rev), true);
		uint256 toSend = prodigy.balanceOf(address(this)) / 20;
		for (uint256 i = 0; i < 5; i++) {
			address add = address(uint160(i) + 11);
			_mockStakers[i] = add;
			prodigy.transfer(add, toSend);
			vm.prank(add);
			prodigy.approve(address(rev), type(uint256).max);
		}
	}

	function test_Stake() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);
		assertEq(prodigy.balanceOf(_mockStakers[0]), 0);
		assertEq(prodigy.balanceOf(address(rev)), stakingBalance);
	}

	function test_RevertWhen_ZeroStake() public {
		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.ZeroAmount.selector);
		rev.stake(0);

		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.ZeroAmount.selector);
		rev.stakeFor(address(0xbeef), 0);
	}

	function test_RevertWhen_InsufficientStake() public {
		_launchToken();
		uint256 minStake = rev.getMinStake();
		vm.expectRevert(ProdigyRevenueShare.InsufficientStake.selector);
		vm.prank(_mockStakers[0]);
		rev.stake(minStake - 1);
	}

	function test_Unstake() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);
		vm.prank(_mockStakers[0]);
		rev.unstake(stakingBalance);
		assertEq(prodigy.balanceOf(_mockStakers[0]), stakingBalance);
		assertEq(prodigy.balanceOf(address(rev)), 0);
	}

	function test_RevertWhen_ZeroUnstake() public {
		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.ZeroAmount.selector);
		rev.unstake(0);
	}

	function test_RevertWhen_UnstakeUnderLimit() public {
		_launchToken();
		prodigy.transfer(_mockStakers[0], 100 ether);
		uint256 minStake = rev.getMinStake();
		vm.prank(_mockStakers[0]);
		rev.stake(minStake);
		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.InsufficientStake.selector);
		rev.unstake(1 ether);
	}

	function test_StakeAndRealise() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);

		uint256 reward = 0.5 ether;
		address(rev).call{value: reward}("");

		uint256 before = _mockStakers[0].balance;
		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 toGet = reward * shared / denominator;

		vm.prank(_mockStakers[0]);
		rev.claim();
		assertEq(_mockStakers[0].balance, before + toGet);
	}

	function test_ManyStakesYield() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[5] memory stakes = [uint256(5 ether), 1 ether, 3 ether, 10 ether, 4 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 reward = 200 ether;
		address(rev).call{value: reward}("");
		uint256 totalStaked = rev.totalPosition();
		for (uint256 i = 0; i < stakes.length; i++) {
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = reward * stakes[i] * shared / denominator / totalStaked;
			assertEq(balanceAfter - balanceBefore, toReceive);
		}
	}

	function test_NewStakeDilution() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[4] memory stakes = [uint256(10 ether), 20 ether, 30 ether, 40 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 reward = 60 ether;
		address(rev).call{value: reward}("");
		uint256 totalStakedBefore = rev.totalPosition();
		vm.prank(_mockStakers[4]);
		rev.stake(50 ether);
		for (uint256 i = 0; i < stakes.length; i++) {
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = reward * stakes[i] * shared / denominator / totalStakedBefore;
			assertEq(balanceAfter - balanceBefore, toReceive);
		}
	}

	function test_Unrealised() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);
		uint256 reward = 1000 gwei;
		address(rev).call{value: reward}("");
		assertEq(rev.getPendingClaim(_mockStakers[0]), reward * shared / denominator);
	}

	function test_Compound() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);

		uint256 reward = 0.5 ether;
		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		address(rev).call{value: reward}("");
		address[] memory buyPath = new address[](2);
		buyPath[0] = _uniswapRouter.WETH();
		buyPath[1] = address(prodigy);

		uint[] memory amounts = _uniswapRouter.getAmountsOut(reward * shared / denominator, buyPath);
		uint256 before = prodigy.balanceOf(address(rev));
		uint256 positionBefore = rev.accountStakedTokens(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.compound(amounts[1]);
		assertEq(prodigy.balanceOf(address(rev)), before + amounts[1]);
		assertEq(rev.accountStakedTokens(_mockStakers[0]), positionBefore + amounts[1]);
	}

	function test_RevertWhen_ZeroCompound() public {
		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.ZeroAmount.selector);
		rev.compound(0);
	}

	function test_CompoundAndStakes() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
	}

	function test_FailPayDev() public {
		// Make sure dev ether receiver cannot receive any ether from the contract.
		assertEq(rev.pendingDevEther(), 0);
		CannotReceiveEther cannot = new CannotReceiveEther();
		rev.setDevReceiver(address(cannot));

		// Expected reward and pending.
		uint256 reward = 1 ether;
		address(rev).call{value: reward}("");
		assertEq(rev.pendingDevEther(), reward);
	}

	function test_AccrueDevPayment() public {
		CannotReceiveEther cannot = new CannotReceiveEther();
		rev.setDevReceiver(address(cannot));
		uint256 reward = 1 ether;
		address(rev).call{value: reward}("");
		assertEq(rev.pendingDevEther(), reward);
		address(rev).call{value: reward}("");
		assertEq(rev.pendingDevEther(), reward * 2);
		rev.setDevReceiver(address(1));
		address(rev).call{value: reward}("");
		assertEq(rev.pendingDevEther(), 0);
	}

	function test_RevertWhen_StakeOnExistingPosition() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		uint256 toStake = stakingBalance / 2;
		vm.prank(_mockStakers[0]);
		rev.stake(toStake);
		vm.expectRevert(ProdigyRevenueShare.AlreadyStaked.selector);
		vm.prank(_mockStakers[0]);
		rev.stake(toStake);
	}

	function test_Restake() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		uint256 toStake = stakingBalance / 2;
		vm.prank(_mockStakers[0]);
		rev.stake(toStake);
		vm.prank(_mockStakers[0]);
		rev.restake(toStake, 0);
		ProdigyRevenueShare.Stake memory position = rev.viewPosition(_mockStakers[0]);
		assertEq(position.amount, toStake * 2);
	}

	function test_RevertWhen_RestakeZero() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		uint256 toStake = stakingBalance / 2;
		vm.prank(_mockStakers[0]);
		rev.stake(toStake);
		vm.prank(_mockStakers[0]);
		vm.expectRevert(ProdigyRevenueShare.ZeroAmount.selector);
		rev.restake(0, 0);
	}

	function test_StakesRestakeClaims() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[4] memory stakes = [uint256(10 ether), 20 ether, 30 ether, 40 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		vm.prank(_mockStakers[3]);
		uint256 restake = 50 ether;
		rev.restake(restake, 0);
		stakes[3] += restake;
		uint256 totalStakedBefore = rev.totalPosition();
		uint256 reward = 600 ether;
		address(rev).call{value: reward}("");
		for (uint256 i = 0; i < stakes.length; i++) {
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = reward * stakes[i] * shared / denominator / totalStakedBefore;
			assertEq(balanceAfter - balanceBefore, toReceive);
		}
	}

	function test_RestakeNoDillution() public {
		_launchToken();
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[4] memory stakes = [uint256(10 ether), 20 ether, 30 ether, 40 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 reward = 60 ether;
		address(rev).call{value: reward}("");
		uint256 totalStakedBefore = rev.totalPosition();
		vm.prank(_mockStakers[3]);
		rev.restake(50 ether, 0);
		for (uint256 i = 0; i < stakes.length; i++) {
			if (i == 3) {
				continue;
			}
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = reward * stakes[i] * shared / denominator / totalStakedBefore;
			assertEq(balanceAfter - balanceBefore, toReceive);
		}
	}

	function testFuzz_StakesClaims(uint256 revenue) public {
		_launchToken();
		vm.assume(revenue > 5 gwei);
		vm.assume(revenue < type(uint88).max);
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[4] memory stakes = [uint256(10 ether), 20 ether, 30 ether, 40 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		uint256 totalStakedBefore = rev.totalPosition();
		address(rev).call{value: revenue}("");
		uint256 totalRevenue = rev.getTotalRevenue();
		assertEq(totalRevenue, revenue * shared / denominator);
		for (uint256 i = 0; i < stakes.length; i++) {
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = revenue * stakes[i] * shared / denominator / totalStakedBefore;
			uint256 balanceFinal = balanceAfter - balanceBefore;
			assertEq(true, balanceFinal == toReceive || balanceFinal + ROUNDING == toReceive);
		}
	}

	function testFuzz_StakesRestakeClaims(uint256 revenue) public {
		_launchToken();
		revenue = bound(revenue, 5 gwei, type(uint88).max);
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256[4] memory stakes = [uint256(10 ether), 20 ether, 30 ether, 40 ether];
		for (uint256 i = 0; i < stakes.length; i++) {
			vm.prank(_mockStakers[i]);
			rev.stake(stakes[i]);
		}

		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();
		vm.prank(_mockStakers[3]);
		uint256 restake = 50 ether;
		rev.restake(restake, 0);
		stakes[3] += restake;
		uint256 totalStakedBefore = rev.totalPosition();
		address(rev).call{value: revenue}("");
		for (uint256 i = 0; i < stakes.length; i++) {
			uint256 balanceBefore = _mockStakers[i].balance;
			vm.prank(_mockStakers[i]);
			rev.claim();
			uint256 balanceAfter = _mockStakers[i].balance;
			uint256 toReceive = revenue * stakes[i] * shared / denominator / totalStakedBefore;
			uint256 balanceFinal = balanceAfter - balanceBefore;
			assertEq(true, balanceFinal == toReceive || balanceFinal + ROUNDING == toReceive);
		}
	}

	function testFuzz_StakeFor(address stakoor) public {
		_launchToken();
		vm.assume(stakoor != _mockStakers[0]);
		rev.setMinStake(1);
		rev.setMinPayout(1);
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stakeFor(stakoor, stakingBalance);
		assertEq(prodigy.balanceOf(_mockStakers[0]), 0);
		assertEq(prodigy.balanceOf(address(rev)), stakingBalance);
		assertEq(rev.accountStakedTokens(stakoor), stakingBalance);
		assertEq(rev.accountStakedTokens(_mockStakers[0]), 0);
	}

	function test_MigrationLock() public {
		_launchToken();

		// Cannot finalise if not started.
		assertEq(rev.migrating(), false);
		vm.expectRevert(ProdigyRevenueShare.CannotMigrate.selector);
		rev.finaliseTwoStepMigration();

		// Start migration.
		prodigy.transfer(address(rev), 1000 ether);
		address(rev).call{value: 1 ether}("");
		address newReceiver = address(0xbeef);
		rev.startTwoStepMigration(newReceiver);
		assertEq(rev.open(), false);
		assertEq(rev.migrating(), true);

		// Too early.
		vm.expectRevert(ProdigyRevenueShare.FinaliseTooEarly.selector);
		rev.finaliseTwoStepMigration();

		// Can finish migration now.
		vm.warp(rev.migrationStarts());
		uint256 tokensInRevShare = prodigy.balanceOf(address(rev));
		uint256 ethInRevShare = address(rev).balance;
		uint256 ethReceiverBefore = address(newReceiver).balance;
		rev.finaliseTwoStepMigration();
		assertEq(address(rev).balance, 0);
		assertEq(prodigy.balanceOf(address(rev)), 0);
		assertEq(address(newReceiver).balance, ethInRevShare + ethReceiverBefore);
		assertEq(prodigy.balanceOf(address(newReceiver)), tokensInRevShare);
	}

	function test_CancelMigration() public {
		assertEq(rev.migrating(), false);
		address newReceiver = address(0xbeef);
		rev.startTwoStepMigration(newReceiver);
		assertEq(rev.open(), false);
		assertEq(rev.migrating(), true);
		rev.cancelMigration();
		assertEq(rev.migrating(), false);
		assertEq(rev.migrationStarts(), 0);
	}

	function testFuzz_FullFlowCombinedActions(
		address staker1, address staker2, address staker3,
		uint256 stake1, uint256 stake2, uint256 stake3,
		uint256 revenue
	) public {
		_launchToken();
		rev.setMinPayout(1);
		rev.setMinStake(1);
		rev.setDevReceiver(address(0x80085));
		prodigy.setTaxExempt(address(rev), true);
		(, uint256 shared, uint256 denominator) = rev.getRevenueShareSettings();

		stake1 = bound(stake1, 1 ether, 100000 ether);
		stake2 = bound(stake2, 1 ether, 100000 ether);
		stake3 = bound(stake3, 1 ether, 100000 ether);
		revenue = bound(revenue, 1 ether, 500 ether);
		vm.assume(staker1 != address(0));
		vm.assume(staker1 != staker2);
		vm.assume(staker1 != staker3);
		vm.assume(staker2 != staker3);
		prodigy.transfer(staker1, stake1);
		prodigy.transfer(staker2, stake2);
		prodigy.transfer(staker3, stake3);

		vm.startPrank(staker1);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake1);
		vm.stopPrank();

		address(rev).call{value: revenue}("");
		uint256 balanceBefore = staker1.balance;
		vm.prank(staker1);
		rev.claim();
		uint256 expectedClaim = (revenue * shared / denominator);
		assertEq(true, staker1.balance - balanceBefore + ROUNDING == expectedClaim || staker1.balance - balanceBefore == expectedClaim);

		vm.startPrank(staker2);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake2);
		vm.stopPrank();
		assertEq(rev.totalPosition(), stake1 + stake2);

		vm.startPrank(staker3);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake3);
		vm.stopPrank();
		assertEq(rev.totalPosition(), stake1 + stake2 + stake3);

		address(rev).call{value: revenue}("");
		vm.startPrank(staker1);
		rev.compound(0);
		rev.unstake(rev.accountStakedTokens(staker1));
		vm.stopPrank();
		assertEq(rev.totalPosition(), stake2 + stake3);

		vm.startPrank(staker2);
		rev.claim();
		rev.unstake(rev.accountStakedTokens(staker2));
		vm.stopPrank();
		assertEq(rev.totalPosition(), stake3);

		vm.startPrank(staker3);
		rev.unstake(rev.accountStakedTokens(staker3));
		vm.stopPrank();
		assertEq(rev.pendingDevEther(), 0);
		assertEq(rev.totalPosition(), 0);
		// Rounding down to avoid giving more eth than owed may lead to dangling wei in the contract.
		assertLe(address(rev).balance, 4);
	}

	function test_CountStakedTokens() public {
		address staker1 = address(0xbeef);
		address staker2 = address(0xdeadbeef);
		address staker3 = address(0x80085);
		uint256 stake = 50 ether;
		prodigy.transfer(staker1, stake);
		prodigy.transfer(staker2, stake);
		prodigy.transfer(staker3, stake);
		vm.startPrank(staker1);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake);
		vm.stopPrank();
		vm.startPrank(staker2);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake);
		vm.stopPrank();
		vm.startPrank(staker3);
		prodigy.approve(address(rev), type(uint256).max);
		rev.stake(stake);
		vm.stopPrank();
		address[] memory stakers = new address[](3);
		stakers[0] = staker1;
		stakers[1] = staker2;
		stakers[2] = staker3;

		assertEq(stake * 3, rev.accountsSumStakedTokens(stakers));
	}

	function test_RecoverToken() public {
		MockERC20 mock = new MockERC20();
		uint256 balanceBefore = mock.balanceOf(address(this));
		uint256 recovery = 50 ether;
		mock.transfer(address(rev), recovery);
		rev.rescueToken(address(mock));
		assertEq(mock.balanceOf(address(rev)), 0);
		assertEq(mock.balanceOf(address(this)), balanceBefore);
	}

	function test_RevertWhen_RecoverProdigyToken() public {
		_launchToken();
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);
		vm.expectRevert(ProdigyRevenueShare.StakingTokenRescue.selector);
		rev.rescueToken(address(prodigy));
	}

	function test_RecoverNonStaking() public {
		_launchToken();
		uint256 stakingBalance = prodigy.balanceOf(_mockStakers[0]);
		vm.prank(_mockStakers[0]);
		rev.stake(stakingBalance);
		uint256 toRecover = 50 ether;
		prodigy.transfer(address(rev), toRecover);
		uint256 balanceBefore = prodigy.balanceOf(address(this));
		rev.rescueNonStakingProdigy();
		assertEq(prodigy.balanceOf(address(this)), balanceBefore + toRecover);
	}
}

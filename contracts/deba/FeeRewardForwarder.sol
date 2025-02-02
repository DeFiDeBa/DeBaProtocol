pragma solidity >0.5.16;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../interfaces/deba/IRewardPool.sol";
import "./../../interfaces/uniswap/IUniswapV2Router02.sol";

contract FeeRewardForwarder {
  using SafeERC20 for IERC20;

  /** 
  *   These are tokens that we are integrating and are interested in.
  *   Tokens that are being used in our vaults/stragies.
  *   Keep & add only those relevant for specific Deba Vaults/Strategies.
  *   They are here in order to build the uniswap paths needed to trade them.
  */
  address constant public ycrv = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
  address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
  address constant public yfi = address(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e);
  address constant public link = address(0x514910771AF9Ca656af840dff83E8264EcF986CA);
  
  mapping (address => mapping (address => address[])) public uniswapRoutes;

  /**
  * The targeted reward token to convert everything to (what the pool needs to receive).
  * This is the token tied to the RewardPool that this FeeRewardForwarder is 
  * connected to at any point in time.
  * If the token that is sent to the Forwarder is the correct one, nothing happens.
  * If it isn't the `targetToken`, then it gets converted to the `targetToken` first.
   */
  address public targetToken; // Is always the RewardPool.rewardToken()
  address public profitSharingPool; // Address of the RewardPool.

  address public uniswapRouterV2;
  
  address public governance;

  event TokenPoolSet(address token, address pool);

  /**
  *   Sets governance address.
  *   Sets the Uniswap router address.
  *   Builds the Uniswap paths.
  */
  constructor(address _storage, address _uniswapRouterV2) public {
    governance = msg.sender;
    require(_uniswapRouterV2 != address(0), "uniswapRouterV2 not defined");
    uniswapRouterV2 = _uniswapRouterV2;
    // these are for mainnet, but they won't impact Ropsten
    uniswapRoutes[ycrv][dai] = [ycrv, weth, dai];
    uniswapRoutes[link][dai] = [link, weth, dai];
    uniswapRoutes[weth][dai] = [weth, dai];
    uniswapRoutes[yfi][dai] = [yfi, weth, dai];
  }

  function setGovernance(address _gov) external {
    require(msg.sender == governance, '!governance');
    governance = _gov;
  }

  /*
  *   Sets the RewardPool that will receive the reward token.
  *   Sets the targetToken of this contract based on 
  *   the address of the RewardPool.
  */
  function setTokenPool(address _pool) public {
    require(msg.sender == governance, '!governance');
    targetToken = IRewardPool(_pool).rewardToken();
    profitSharingPool = _pool;
    emit TokenPoolSet(targetToken, _pool);
  }

  /**
  *   Sets the path for swapping tokens to the to address
  *   The `to` address is not validated to match the targetToken,
  *   so that we could first update the paths, and then,
  *   set the new target.
  */
  function setConversionPath(address from, address to, address[] memory _uniswapRoute) public {
    require(msg.sender == governance, '!governance');
    require(from == _uniswapRoute[0],
      "The first token of the Uniswap route must be the from token");
    require(to == _uniswapRoute[_uniswapRoute.length - 1],
      "The last token of the Uniswap route must be the to token");
    uniswapRoutes[from][to] = _uniswapRoute;
  }

  /**
  * Main Function
  *
  * Forwards the funds from the msg.sender to the pool
  * under normal circumstances, msg.sender is the strategy.
  */
  function poolNotifyFixedTarget(address _token, uint256 _amount) external {
    if (targetToken == address(0)) {
      return; // a No-op if target pool is not set yet
    }
    if (_token == targetToken) {
      // this is already the right token
      IERC20(_token).safeTransferFrom(msg.sender, profitSharingPool, _amount);
      IRewardPool(profitSharingPool).notifyRewardAmount(_amount);
    } else {
      // we need to convert
      if (uniswapRoutes[_token][targetToken].length > 1) {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceToSwap = IERC20(_token).balanceOf(address(this));

        IERC20(_token).safeApprove(uniswapRouterV2, 0);
        IERC20(_token).safeApprove(uniswapRouterV2, balanceToSwap);

        IUniswapV2Router02(uniswapRouterV2).swapExactTokensForTokens(
          balanceToSwap,
          1, // we will accept any amount
          uniswapRoutes[_token][targetToken],
          address(this),
          block.timestamp
        );
        // now we can send this token forward
        uint256 convertedRewardAmount = IERC20(targetToken).balanceOf(address(this));
        IERC20(targetToken).safeTransfer(profitSharingPool, convertedRewardAmount);
        IRewardPool(profitSharingPool).notifyRewardAmount(convertedRewardAmount);
      }
      // else the route does not exist for this token
      // do not take any fees
    }
  }
}

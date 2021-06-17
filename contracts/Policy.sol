// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {WadRayMath} from './WadRayMath.sol';
import {IRiskModule} from '../interfaces/IRiskModule.sol';

library Policy {
  using WadRayMath for uint256;

  uint256 public constant SECONDS_IN_YEAR = 31536000e18; /* 365 * 24 * 3600 * 10e18 */
  uint256 public constant SECONDS_IN_YEAR_RAY = 31536000e27; /* 365 * 24 * 3600 * 10e27 */

  // Active Policies
  struct PolicyData {
    uint256 id;
    uint256 payout;
    uint256 premium;
    uint256 scr;
    uint256 rmCoverage;     // amount of the payout covered by risk_module
    uint256 lossProb;       // original loss probability (in ray)
    uint256 purePremium;    // share of the premium that covers expected losses
                            // equal to payout * lossProb * riskModule.moc
    uint256 premiumForEnsuro; // share of the premium that goes for Ensuro (if policy won)
    uint256 premiumForRm;     // share of the premium that goes for the RM (if policy won)
    uint256 premiumForLps;    // share of the premium that goes to the liquidity providers (won or not)
    IRiskModule riskModule;
    uint40 start;
    uint40 expiration;
  }

  function initialize(IRiskModule riskModule, uint256 premium, uint256 payout,
                      uint256 lossProb, uint40 expiration) public returns (PolicyData memory) {
    require(premium <= payout);
    PolicyData memory policy;
    policy.riskModule = riskModule;
    policy.premium = premium;
    policy.payout = payout;
    policy.rmCoverage = payout.wadToRay().rayMul(riskModule.sharedCoveragePercentage()).rayToWad();
    policy.lossProb = lossProb;
    uint256 ens_premium = policy.premium.wadMul(policy.payout - policy.rmCoverage).wadDiv(policy.payout);
    uint256 rm_premium = policy.premium - ens_premium;
    policy.scr = (payout - ens_premium - policy.rmCoverage).wadMul(
      riskModule.scrPercentage().rayToWad()
    );
    require(policy.scr != 0, "SCR can't be zero");
    policy.start = uint40(block.timestamp);
    policy.expiration = expiration;
    policy.purePremium = (
      payout - policy.rmCoverage
    ).wadToRay().rayMul(lossProb.rayMul(riskModule.moc())).rayToWad();
    uint256 profitPremium = ens_premium - policy.purePremium;
    policy.premiumForEnsuro = profitPremium.wadMul(riskModule.ensuroShare().rayToWad());
    policy.premiumForRm = profitPremium.wadMul(riskModule.premiumShare().rayToWad());
    policy.premiumForLps = profitPremium - policy.premiumForEnsuro - policy.premiumForRm;
    policy.premiumForRm += rm_premium;
    return policy;
  }

  function rmScr(PolicyData storage policy) public returns (uint256) {
    uint256 ens_premium = policy.premium.wadMul(policy.payout - policy.rmCoverage).wadDiv(policy.payout);
    return policy.rmCoverage - (policy.premium - ens_premium);
  }

  function interestRate(PolicyData storage policy) public returns (uint256) {
    return policy.premiumForLps.wadMul(SECONDS_IN_YEAR).wadDiv(
      (policy.expiration - policy.start) * policy.scr
    ).wadToRay();
  }

  function accruedInterest(PolicyData storage policy) public returns (uint256) {
    uint256 secs = block.timestamp - policy.start;
    return policy.scr.wadToRay().rayMul(
      secs * interestRate(policy)
    ).rayDiv(SECONDS_IN_YEAR_RAY).rayToWad();
  }

  // For debugging
  function uint2str(uint _i) public pure returns (string memory _uintAsString) {
    if (_i == 0) {
      return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len;
    while (_i != 0) {
        k = k-1;
        uint8 temp = (48 + uint8(_i - _i / 10 * 10));
        bytes1 b1 = bytes1(temp);
        bstr[k] = b1;
        _i /= 10;
    }
    return string(bstr);
   }
}
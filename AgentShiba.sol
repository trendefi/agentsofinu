/** 
Agent Shiba - Agents of I.N.U.

Agent Shiba, from the Agents of I.N.U. is our utility token that gives you access to the Agents of I.N.U. Crypto Tracker. 
Our Crypto Tracker is live now, ready to help you make smarter DeFi investments.

Website: https://agentsinu.com
Web app: https://app.agentsinu.com
Twitter: twitter.com/AgentsOfInu
Telegram: https://t.me/AgentsOfInuAgentShiba
 */

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract AgentShiba is Context, IERC20 {
    // Ownership moved to in-contrsact for customizability.
    address private _owner;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => bool) lpPairs;
    uint256 private timeSinceLastPair = 0;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    mapping (address => bool) private _liquidityHolders;

    mapping(address => bool) public isBlacklisted;

    uint256 private startingSupply;

    string private _name;
    string private _symbol;

    struct FeesStruct {
        uint16 reflectFee;
        uint16 liquidityFee;
        uint16 marketingFee;
    }

    struct StaticValuesStruct {
        uint16 maxReflectFee;
        uint16 maxLiquidityFee;
        uint16 maxMarketingFee;
        uint16 masterTaxDivisor;
    }

    struct Ratios {
        uint16 liquidityRatio;
        uint16 marketingRatio;
        uint16 totalRatio;
    }

    FeesStruct private currentTaxes = FeesStruct({
        reflectFee: 0,
        liquidityFee: 0,
        marketingFee: 0
        });

    FeesStruct public buyTaxes = FeesStruct({
        reflectFee: 200,
        liquidityFee: 100,
        marketingFee: 800
        });

    FeesStruct public sellTaxes = FeesStruct({
        reflectFee: 200,
        liquidityFee: 100,
        marketingFee: 800
        });

    FeesStruct public transferTaxes = FeesStruct({
        reflectFee: 200,
        liquidityFee: 100,
        marketingFee: 800
        });

    Ratios public ratios = Ratios({
        liquidityRatio: buyTaxes.liquidityFee,
        marketingRatio: buyTaxes.marketingFee,
        totalRatio: buyTaxes.liquidityFee + buyTaxes.marketingFee
        });

    StaticValuesStruct public staticVals = StaticValuesStruct({
        maxReflectFee: 800,
        maxLiquidityFee: 800,
        maxMarketingFee: 1000,
        masterTaxDivisor: 10000
        });

    uint256 private constant MAX = ~uint256(0);
    uint8 private _decimals;
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    IUniswapV2Router02 public dexRouter;
    address public lpPair;

    // UNI ROUTER
    address private _routerAddress;

    address constant public DEAD = 0x000000000000000000000000000000000000dEaD;
    address payable private _marketingWallet;
    
    bool inSwap;
    bool public contractSwapEnabled = false;
    
    uint256 private _maxTxAmount;
    uint256 public maxTxAmount;

    uint256 private _maxWalletSize;
    uint256 public maxWalletSize;

    uint256 private swapThreshold;
    uint256 private swapAmount;

    bool public tradingEnabled = false;
    bool public _hasLiqBeenAdded = false;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event ContractSwapEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Caller =/= owner.");
        _;
    }
    
    constructor (string memory name_, 
    string memory symbol_, 
    address payable marketingWallet,
    address routerAddress
    ) payable {

        _routerAddress = routerAddress;

        // Set the owner.
        _owner = msg.sender;
        _approve(_msgSender(), _routerAddress, type(uint256).max);
        _approve(address(this), _routerAddress, type(uint256).max);

        _name = name_;
        _symbol = symbol_;

        _marketingWallet = payable(marketingWallet);

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;
        _liquidityHolders[owner()] = true;
    }
    
    bool contractInitialized = false;

    function initializeContract(address[] memory accounts, uint256[] memory amounts) external onlyOwner {
        require(!contractInitialized, "Contract already initialized.");
        require(accounts.length < 50, "Max 50 wallets.");
        require(accounts.length == amounts.length, "Must be equal lengths.");

        startingSupply = 1_000_000_000_000_000;
        if (startingSupply < 10000000000) {
            _decimals = 18;
        } else {
            _decimals = 9;
        }
        _tTotal = startingSupply * (10**_decimals);
        _rTotal = (MAX - (MAX % _tTotal));

        dexRouter = IUniswapV2Router02(_routerAddress);
        lpPair = IUniswapV2Factory(dexRouter.factory()).createPair(dexRouter.WETH(), address(this));
        lpPairs[lpPair] = true;

        uint256 percent = 3;
        uint256 divisor = 1000;
        _maxTxAmount = (_tTotal * percent) / divisor;
        maxTxAmount = (startingSupply * percent) / divisor;

        percent = 200;
        divisor = 10000;
        _maxWalletSize = (_tTotal * percent) / divisor;
        maxWalletSize = (startingSupply * percent) / divisor;

        swapThreshold = (_tTotal * 5) / 10000;
        swapAmount = (_tTotal * 5) / 1000;

        contractInitialized = true;     
        _rOwned[owner()] = _rTotal;
        emit Transfer(address(0), owner(), _tTotal);

        _approve(address(this), address(dexRouter), type(uint256).max);

        for(uint256 i = 0; i < accounts.length; i++){
            address wallet = accounts[i];
            uint256 amount = amounts[i]*10**_decimals;
            _transfer(owner(), wallet, amount);
        }

        _transfer(owner(), address(this), balanceOf(owner()));

        dexRouter.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

        enableTrading();
    }

    receive() external payable {}

//===============================================================================================================
//===============================================================================================================
//===============================================================================================================
    // Ownable removed as a lib and added here to allow for custom transfers and recnouncements.
    // This allows for removal of ownership privelages from the owner once renounced or transferred.
    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwner(address newOwner) external onlyOwner() {
        require(newOwner != address(0), "Call renounceOwnership to transfer owner to the zero address.");
        require(newOwner != DEAD, "Call renounceOwnership to transfer owner to the zero address.");
        setExcludedFromFees(_owner, false);
        setExcludedFromFees(newOwner, true);
        if (tradingEnabled){
            setExcludedFromReward(newOwner, true);
        }
        
        if (_marketingWallet == payable(_owner))
            _marketingWallet = payable(newOwner);
        
        if(balanceOf(_owner) > 0) {
            _transfer(_owner, newOwner, balanceOf(_owner));
        }
        
        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
        
    }

    function renounceOwnership() public virtual onlyOwner() {
        setExcludedFromFees(_owner, false);
        _owner = address(0);
        emit OwnershipTransferred(_owner, address(0));
    }

//===============================================================================================================
//===============================================================================================================
//===============================================================================================================

    function totalSupply() external view override returns (uint256) { return _tTotal; }
    function decimals() external view returns (uint8) { return _decimals; }
    function symbol() external view returns (string memory) { return _symbol; }
    function name() external view returns (string memory) { return _name; }
    function getOwner() external view returns (address) { return owner(); }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address sender, address spender, uint256 amount) private {
        require(sender != address(0), "ERC20: Zero Address");
        require(spender != address(0), "ERC20: Zero Address");

        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
    }

    function approveContractContingency() public onlyOwner returns (bool) {
        _approve(address(this), address(dexRouter), type(uint256).max);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] -= amount;
        }

        return _transfer(sender, recipient, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
        return true;
    }

    function setNewRouter(address newRouter) public onlyOwner() {
        IUniswapV2Router02 _newRouter = IUniswapV2Router02(newRouter);
        address get_pair = IUniswapV2Factory(_newRouter.factory()).getPair(address(this), _newRouter.WETH());
        if (get_pair == address(0)) {
            lpPair = IUniswapV2Factory(_newRouter.factory()).createPair(address(this), _newRouter.WETH());
        }
        else {
            lpPair = get_pair;
        }
        dexRouter = _newRouter;
        _approve(address(this), address(dexRouter), type(uint256).max);
    }

    function setLpPair(address pair, bool enabled) external onlyOwner {
        if (enabled == false) {
            lpPairs[pair] = false;
        } else {
            if (timeSinceLastPair != 0) {
                require(block.timestamp - timeSinceLastPair > 1 weeks, "Cannot set a new pair this week!");
            }
            lpPairs[pair] = true;
            timeSinceLastPair = block.timestamp;
        }
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function setExcludedFromFees(address account, bool enabled) public onlyOwner {
        _isExcludedFromFees[account] = enabled;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function setExcludedFromReward(address account, bool enabled) public onlyOwner {
        if (enabled == true) {
            require(!_isExcluded[account], "Account is already excluded.");
            if(_rOwned[account] > 0) {
                _tOwned[account] = tokenFromReflection(_rOwned[account]);
            }
            _isExcluded[account] = true;
            _excluded.push(account);
        } else if (enabled == false) {
            require(_isExcluded[account], "Account is already included.");
            if(_excluded.length == 1){
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
            } else {
                for (uint256 i = 0; i < _excluded.length; i++) {
                    if (_excluded[i] == account) {
                        _excluded[i] = _excluded[_excluded.length - 1];
                        _tOwned[account] = 0;
                        _isExcluded[account] = false;
                        _excluded.pop();
                        break;
                    }
                }
            }
        }
    }
    
    function setBuyTaxes(uint16 reflectFee, uint16 liquidityFee, uint16 marketingFee) external onlyOwner {
        require(reflectFee <= staticVals.maxReflectFee
                && liquidityFee <= staticVals.maxLiquidityFee
                && marketingFee <= staticVals.maxMarketingFee, "Individual fees exceeded maximum");
        require(liquidityFee + reflectFee + marketingFee <= 2000, "Total fees exceeded maximum");
        buyTaxes.liquidityFee = liquidityFee;
        buyTaxes.reflectFee = reflectFee;
        buyTaxes.marketingFee = marketingFee;
    }

    function setSellTaxes(uint16 reflectFee, uint16 liquidityFee, uint16 marketingFee) external onlyOwner {
        require(reflectFee <= staticVals.maxReflectFee
                && liquidityFee <= staticVals.maxLiquidityFee
                && marketingFee <= staticVals.maxMarketingFee, "Individual fees exceeded maximum");
        require(liquidityFee + reflectFee + marketingFee <= 2000, "Total fees exceeded maximum");
        sellTaxes.liquidityFee = liquidityFee;
        sellTaxes.reflectFee = reflectFee;
        sellTaxes.marketingFee = marketingFee;
    }

    function setTransferTaxes(uint16 reflectFee, uint16 liquidityFee, uint16 marketingFee) external onlyOwner {
        require(reflectFee <= staticVals.maxReflectFee
                && liquidityFee <= staticVals.maxLiquidityFee
                && marketingFee <= staticVals.maxMarketingFee, "Individual fees exceeded maximum");
        require(liquidityFee + reflectFee + marketingFee <= 2000, "Total fees exceeded maximum");
        transferTaxes.liquidityFee = liquidityFee;
        transferTaxes.reflectFee = reflectFee;
        transferTaxes.marketingFee = marketingFee;
    }

    function setRatios(uint16 liquidity, uint16 marketing) external onlyOwner {
        require (liquidity + marketing == 100, "Must add up to 100%");
        ratios.liquidityRatio = liquidity;
        ratios.marketingRatio = marketing;
        ratios.totalRatio = liquidity + marketing;
    }

    function setMaxTxPercent(uint256 percent, uint256 divisor) external onlyOwner {
        uint256 check = (_tTotal * percent) / divisor;
        require(check >= (_tTotal / 1000), "Max TX cannot be below 0.1% of supply");
        _maxTxAmount = check;
        maxTxAmount = (startingSupply * percent) / divisor;
    }

    function setMaxWalletSize(uint256 percent, uint256 divisor) external onlyOwner {
        uint256 check = (_tTotal * percent) / divisor;
        require(check >= (_tTotal / 500), "Max Wallet cannot be below 0.2% of supply");
        _maxWalletSize = check;
        maxWalletSize = (startingSupply * percent) / divisor;
    }

    function setSwapSettings(uint256 thresholdPercent, uint256 thresholdDivisor, uint256 amountPercent, uint256 amountDivisor) external onlyOwner {
        swapThreshold = (_tTotal * thresholdPercent) / thresholdDivisor;
        swapAmount = (_tTotal * amountPercent) / amountDivisor;
    }

    function setMarketingWallet(address payable marketingWallet) external onlyOwner {
        _marketingWallet = payable(marketingWallet);
    }

    function blacklistAddress(address account, bool blacklist) external onlyOwner {
        require (account != address(0), "Can't set zero address as blacklist address");
        require (account != address(owner()), "Can't set owner address as blacklist address");
        require (!lpPairs[account], "Can't set lp address as blacklist address");

        isBlacklisted[account] = blacklist;
    }

    function setContractSwapEnabled(bool _enabled) public onlyOwner {
        contractSwapEnabled = _enabled;
        emit ContractSwapEnabledUpdated(_enabled);
    }

    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading already enabled!");
        require(_hasLiqBeenAdded, "Liquidity must be added.");
        setExcludedFromReward(address(this), true);
        setExcludedFromReward(lpPair, true);
        tradingEnabled = true;
    }

    function sweepContingency() external onlyOwner {
        require(!_hasLiqBeenAdded, "Cannot call after liquidity.");
        payable(owner()).transfer(address(this).balance);
    }

    function _hasLimits(address from, address to) private view returns (bool) {
        return from != owner()
            && to != owner()
            && !_liquidityHolders[to]
            && !_liquidityHolders[from]
            && to != DEAD
            && to != address(0)
            && from != address(this);
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount / currentRate;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require (!isBlacklisted[from] && !isBlacklisted[to], "Blacklisted address");

        if(_hasLimits(from, to)) {
            if(!tradingEnabled) {
                revert("Trading not yet enabled!");
            }

            if(lpPairs[from] || lpPairs[to]){
                require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
            }
            if(to != _routerAddress && !lpPairs[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "Transfer amount exceeds the maxWalletSize.");
            }
        }

        bool takeFee = true;
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]){
            takeFee = false;
        }

        if (lpPairs[to]) {
            if (!inSwap
                && contractSwapEnabled
            ) {
                uint256 contractTokenBalance = balanceOf(address(this));
                if (contractTokenBalance >= swapThreshold) {
                    if(contractTokenBalance >= swapAmount) { contractTokenBalance = swapAmount; }
                    contractSwap(contractTokenBalance);
                }
            }      
        } 
        return _finalizeTransfer(from, to, amount, takeFee);
    }

    function contractSwap(uint256 contractTokenBalance) private lockTheSwap {
        if (ratios.totalRatio == 0)
            return;

        if(_allowances[address(this)][address(dexRouter)] != type(uint256).max) {
            _allowances[address(this)][address(dexRouter)] = type(uint256).max;
        }

        uint256 toLiquify = ((contractTokenBalance * ratios.liquidityRatio) / ratios.totalRatio) / 2;

        uint256 toSwapForEth = contractTokenBalance - toLiquify;
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            toSwapForEth,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint256 liquidityBalance = ((address(this).balance * ratios.liquidityRatio) / ratios.totalRatio) / 2;

        if (toLiquify > 0) {
            dexRouter.addLiquidityETH{value: liquidityBalance}(
                address(this),
                toLiquify,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                DEAD,
                block.timestamp
            );
            emit SwapAndLiquify(toLiquify, liquidityBalance, toLiquify);
        }
        if (contractTokenBalance - toLiquify > 0) {
            _marketingWallet.transfer(address(this).balance);
        }
    }

    function _checkLiquidityAdd(address from, address to) private {
        require(!_hasLiqBeenAdded, "Liquidity already added and marked.");
        if (!_hasLimits(from, to) && to == lpPair) {
            if (from == address(this)){
                _liquidityHolders[owner()] = true;
            } else {
                _liquidityHolders[from] = true;
            }
            _hasLiqBeenAdded = true;
            contractSwapEnabled = true;
            emit ContractSwapEnabledUpdated(true);
        }
    }

    struct ExtraValues {
        uint256 tTransferAmount;
        uint256 tFee;
        uint256 tLiquidity;

        uint256 rTransferAmount;
        uint256 rAmount;
        uint256 rFee;
    }

    function _finalizeTransfer(address from, address to, uint256 tAmount, bool takeFee) private returns (bool) {
        if (!_hasLiqBeenAdded) {
            _checkLiquidityAdd(from, to);
            if (!_hasLiqBeenAdded && _hasLimits(from, to)) {
                revert("Only owner can transfer at this time.");
            }
        }

        ExtraValues memory values = _getValues(from, to, tAmount, takeFee);

        _rOwned[from] = _rOwned[from] - values.rAmount;
        _rOwned[to] = _rOwned[to] + values.rTransferAmount;

        if (_isExcluded[from] && !_isExcluded[to]) {
            _tOwned[from] = _tOwned[from] - tAmount;
        } else if (!_isExcluded[from] && _isExcluded[to]) {
            _tOwned[to] = _tOwned[to] + values.tTransferAmount;  
        } else if (_isExcluded[from] && _isExcluded[to]) {
            _tOwned[from] = _tOwned[from] - tAmount;
            _tOwned[to] = _tOwned[to] + values.tTransferAmount;
        }

        if (values.tLiquidity > 0) {
            _takeLiquidity(from, values.tLiquidity);
        }

        if (values.rFee > 0 || values.tFee > 0) {
            _rTotal -= values.rFee;
            _tFeeTotal += values.tFee;
        }

        emit Transfer(from, to, values.tTransferAmount);
        return true;
    }

    function _getValues(address from, address to, uint256 tAmount, bool takeFee) private returns (ExtraValues memory) {
        ExtraValues memory values;
        uint256 currentRate = _getRate();
        values.rAmount = tAmount * currentRate;

        if(takeFee) {
            if (lpPairs[to]) {
                currentTaxes.reflectFee = sellTaxes.reflectFee;
                currentTaxes.liquidityFee = sellTaxes.liquidityFee;
                currentTaxes.marketingFee = sellTaxes.marketingFee;
            } else if (lpPairs[from]) {
                currentTaxes.reflectFee = buyTaxes.reflectFee;
                currentTaxes.liquidityFee = buyTaxes.liquidityFee;
                currentTaxes.marketingFee = buyTaxes.marketingFee;
            } else {
                currentTaxes.reflectFee = transferTaxes.reflectFee;
                currentTaxes.liquidityFee = transferTaxes.liquidityFee;
                currentTaxes.marketingFee = transferTaxes.marketingFee;
            }

            values.tFee = (tAmount * currentTaxes.reflectFee) / staticVals.masterTaxDivisor;
            values.tLiquidity = (tAmount * (currentTaxes.liquidityFee + currentTaxes.marketingFee)) / staticVals.masterTaxDivisor;
            values.tTransferAmount = tAmount - (values.tFee + values.tLiquidity);

            values.rFee = values.tFee * currentRate;
        } else {
            values.tFee = 0;
            values.tLiquidity = 0;
            values.tTransferAmount = tAmount;

            values.rFee = 0;
        }
        values.rTransferAmount = values.rAmount - (values.rFee + (values.tLiquidity * currentRate));
        return values;
    }

    function _getRate() private view returns(uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return _rTotal / _tTotal;
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return _rTotal / _tTotal;
        return rSupply / tSupply;
    }
    
    function _takeLiquidity(address sender, uint256 tLiquidity) private {
        _rOwned[address(this)] = _rOwned[address(this)] + (tLiquidity * _getRate());
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] + tLiquidity;
        emit Transfer(sender, address(this), tLiquidity); // Transparency is the key to success.
    }
}
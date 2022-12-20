module defi::animeswap {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    // use std::option;
    use sui::balance::{Self, Supply, Balance};
    // use sui::sui::SUI;
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};
    use std::type_name;
    use std::ascii::String;
    use sui::dynamic_object_field as ofield;
    use defi::animeswap_library::{quote, sqrt, get_amount_out, get_amount_in, compare};
    // use std::debug;

    /// When contract error
    const ERR_INTERNAL_ERROR: u64 = 102;
    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 103;
    /// When not enough amount for pool
    const ERR_INSUFFICIENT_AMOUNT: u64 = 104;
    /// When not enough liquidity amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 105;
    /// When not enough liquidity minted
    const ERR_INSUFFICIENT_LIQUIDITY_MINT: u64 = 106;
    /// When not enough liquidity burned
    const ERR_INSUFFICIENT_LIQUIDITY_BURN: u64 = 107;
    /// When not enough X amount
    const ERR_INSUFFICIENT_X_AMOUNT: u64 = 108;
    /// When not enough Y amount
    const ERR_INSUFFICIENT_Y_AMOUNT: u64 = 109;
    /// When not enough input amount
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 110;
    /// When not enough output amount
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 111;
    /// When contract K error
    const ERR_K_ERROR: u64 = 112;
    /// When already exists on account
    const ERR_PAIR_ALREADY_EXIST: u64 = 115;
    /// When not exists on account
    const ERR_PAIR_NOT_EXIST: u64 = 116;
    /// When error loan amount
    const ERR_LOAN_ERROR: u64 = 117;
    /// When contract is not reentrant
    const ERR_LOCK_ERROR: u64 = 118;
    /// When pair has wrong ordering
    const ERR_PAIR_ORDER_ERROR: u64 = 119;
    /// When contract is paused
    const ERR_PAUSABLE_ERROR: u64 = 120;
    /// When input value not satisfied
    const ERR_INPUT_VALUE: u64 = 121;

    const MINIMUM_LIQUIDITY: u64 = 1000;

    struct LPCoin<phantom X, phantom Y> has drop {}

    struct LiquidityPool<phantom X, phantom Y> has key, store {
        id: UID,
        coin_x_reserve: Balance<X>,
        coin_y_reserve: Balance<Y>,
        lp_coin_reserve: Balance<LPCoin<X, Y>>,
        lp_supply: Supply<LPCoin<X, Y>>,
    }

    // global config
    struct AdminData has store, copy, drop {
        dao_fee_to: address,
        admin_address: address,
        dao_fee: u64,           // 1/(dao_fee+1) comes to dao_fee_to if dao_fee_on
        swap_fee: u64,          // BP, swap_fee * 1/10000
        dao_fee_on: bool,       // default: true
        is_pause: bool,         // pause swap
    }

    /// LiquidityPool is dynamically added to this
    struct LiquidityPools has key {
        id: UID,
        admin_data: AdminData,
    }

    /// To publish a new Pool one has to create a type which will mark LPCoins.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(LiquidityPools {
            id: object::new(ctx),
            admin_data: AdminData {
                dao_fee_to: @deployer,
                admin_address: @deployer,
                dao_fee: 5,
                swap_fee: 30,
                dao_fee_on: true,
                is_pause: false,
            }
        });
    }

    public fun get_lp_name<X, Y>(): String {
        type_name::into_string(type_name::get<LPCoin<X, Y>>())
    }

    /// get reserves size
    /// always return (X_reserve, Y_reserve)
    public fun get_reserves_size<X, Y>(pool: &LiquidityPool<X, Y>): (u64, u64) {
        (balance::value(&pool.coin_x_reserve), balance::value(&pool.coin_y_reserve))
    }

    /// get amounts out, 1 pair
    public fun get_amounts_out<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_in: u64,
        x_y: bool,
    ): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
        if (!x_y) {
            (reserve_in, reserve_out) = (reserve_out, reserve_in);
        };
        let amount_out = get_amount_out(amount_in, reserve_in, reserve_out, 0);
        amount_out
    }

    /// get amounts in, 1 pair
    public fun get_amounts_in<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_out: u64,
        x_y: bool,
    ): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
        if (!x_y) {
            (reserve_in, reserve_out) = (reserve_out, reserve_in);
        };
        let amount_in = get_amount_in(amount_out, reserve_in, reserve_out, 0);
        amount_in
    }

    /// return remaining coin.
    public fun return_remaining_coin<X>(
        coin: Coin<X>,
        ctx: &mut TxContext,
    ) {
        if (coin::value(&coin) == 0) {
            coin::destroy_zero(coin);
        } else {
            transfer::transfer(coin, tx_context::sender(ctx));
        };
    }

    /// Calculate optimal amounts of coins to add
    public fun calc_optimal_coin_values<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ): (u64, u64) {
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        if (reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_y_optimal = quote(amount_x_desired, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y_desired) {
                assert!(amount_y_optimal >= amount_y_min, ERR_INSUFFICIENT_Y_AMOUNT);
                (amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = quote(amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x_desired, ERR_INTERNAL_ERROR);
                assert!(amount_x_optimal >= amount_x_min, ERR_INSUFFICIENT_X_AMOUNT);
                (amount_x_optimal, amount_y_desired)
            }
        }
    }

    /// get pool
    public fun get_pool<X, Y>(
        lps: &mut LiquidityPools,
    ): (&mut LiquidityPool<X, Y>, AdminData) {
        let pool = ofield::borrow_mut<String, LiquidityPool<X, Y>>(
            &mut lps.id, get_lp_name<X, Y>()
        );
        (pool, lps.admin_data)
    }

    /// create pair entry function
    /// require X < Y
    public entry fun create_pair_entry<X, Y>(
        lps: &mut LiquidityPools,
        ctx: &mut TxContext,
    ) {
        assert!(compare<X, Y>(), ERR_PAIR_ORDER_ERROR);
        assert!(!ofield::exists_<String>(&mut lps.id, get_lp_name<X, Y>()), ERR_PAIR_ALREADY_EXIST);
        let lp = LiquidityPool<X, Y> {
            id: object::new(ctx),
            coin_x_reserve: balance::zero<X>(),
            coin_y_reserve: balance::zero<Y>(),
            lp_coin_reserve: balance::zero(),
            lp_supply: balance::create_supply(LPCoin<X, Y> {}),
        };
        ofield::add(&mut lps.id, get_lp_name<X, Y>(), lp);
    }

    /// add liqudity entry function
    /// require X < Y
    public entry fun add_liquidity_entry<X, Y>(
        lps: &mut LiquidityPools,
        coin_x_origin: Coin<X>,
        coin_y_origin: Coin<Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ) {
        let lp_coins = add_liquidity<X, Y>(
            lps,
            coin_x_origin,
            coin_y_origin,
            amount_x_desired,
            amount_y_desired,
            amount_x_min,
            amount_y_min,
            ctx,
        );
        transfer::transfer(lp_coins, tx_context::sender(ctx));
    }

    /// remove liqudity entry function
    /// require X < Y
    public entry fun remove_liquidity_entry<X, Y>(
        lps: &mut LiquidityPools,
        liquidity: Coin<LPCoin<X, Y>>,
        liquidity_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ) {
        let (coin_x, coin_y) = remove_liquidity<X, Y>(
            lps,
            liquidity,
            liquidity_desired,
            amount_x_min,
            amount_y_min,
            ctx,
        );
        transfer::transfer(coin_x, tx_context::sender(ctx));
        transfer::transfer(coin_y, tx_context::sender(ctx));
    }

    /// add liqudity
    /// require X < Y
    public fun add_liquidity<X, Y>(
        lps: &mut LiquidityPools,
        coin_x_origin: Coin<X>,
        coin_y_origin: Coin<Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ): Coin<LPCoin<X, Y>> {
        let (pool, admin_data) = get_pool<X, Y>(lps);
        let amt_x = coin::value(&coin_x_origin);
        let amt_y = coin::value(&coin_y_origin);

        assert!(amt_x >= amount_x_desired
            && amount_x_desired >= amount_x_min
            && amount_x_min > 0,
            ERR_INSUFFICIENT_X_AMOUNT);
        assert!(amt_y >= amount_y_desired
            && amount_y_desired >= amount_y_min
            && amount_y_min > 0,
            ERR_INSUFFICIENT_Y_AMOUNT);

        let (amount_x, amount_y) =
            calc_optimal_coin_values<X, Y>(pool, amount_x_desired, amount_y_desired, amount_x_min, amount_y_min);
        let coin_x = coin::split(&mut coin_x_origin, amount_x, ctx);
        let coin_y = coin::split(&mut coin_y_origin, amount_y, ctx);
        let lp_balance = mint<X, Y>(pool, admin_data, coin::into_balance<X>(coin_x), coin::into_balance<Y>(coin_y));
        let lp_coins = coin::from_balance<LPCoin<X, Y>>(lp_balance, ctx);
        return_remaining_coin(coin_x_origin, ctx);
        return_remaining_coin(coin_y_origin, ctx);
        lp_coins
    }

    /// remove liqudity
    /// require X < Y
    public fun remove_liquidity<X, Y>(
        lps: &mut LiquidityPools,
        liquidity: Coin<LPCoin<X, Y>>,
        liquidity_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        let (pool, admin_data) = get_pool<X, Y>(lps);
        let amt_lp = coin::value(&liquidity);
        assert!(amt_lp >= liquidity_desired, ERR_INSUFFICIENT_INPUT_AMOUNT);
        let coin_lp = coin::split(&mut liquidity, liquidity_desired, ctx);
        let (x_balance, y_balance) = burn<X, Y>(pool, admin_data, coin::into_balance(coin_lp));
        let x_out = coin::from_balance(x_balance, ctx);
        let y_out = coin::from_balance(y_balance, ctx);
        assert!(coin::value(&x_out) >= amount_x_min, ERR_INSUFFICIENT_X_AMOUNT);
        assert!(coin::value(&y_out) >= amount_y_min, ERR_INSUFFICIENT_Y_AMOUNT);
        return_remaining_coin(liquidity, ctx);
        (x_out, y_out)
    }

    /// entry, swap from exact X to Y
    /// no require for X Y order
    public entry fun swap_exact_coins_for_coins<X, Y>(
        lps: &mut LiquidityPools,
        coins_in_origin: Coin<X>,
        amount_in: u64,
        amount_out_min: u64,
        ctx: &mut TxContext,
    ) {
        if (compare<X, Y>()) {
            let pool = ofield::borrow_mut<String, LiquidityPool<X, Y>>(&mut lps.id, get_lp_name<X, Y>());
            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (zero, coins_out) = swap_coins_for_coins<X, Y>(pool, coins_in, coin::zero(ctx), ctx);
            coin::destroy_zero(zero);
            assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
            return_remaining_coin(coins_in_origin, ctx);
            transfer::transfer(coins_out, tx_context::sender(ctx));
        } else {
            let pool = ofield::borrow_mut<String, LiquidityPool<Y, X>>(&mut lps.id, get_lp_name<Y, X>());
            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (coins_out, zero) = swap_coins_for_coins<Y, X>(pool, coin::zero(ctx), coins_in, ctx);
            coin::destroy_zero(zero);
            assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
            return_remaining_coin(coins_in_origin, ctx);
            transfer::transfer(coins_out, tx_context::sender(ctx));
        }
    }

    /// entry, swap from X to exact Y
    /// no require for X Y order
    public entry fun swap_coins_for_exact_coins<X, Y>(
        lps: &mut LiquidityPools,
        coins_in_origin: Coin<X>,
        amount_out: u64,
        amount_in_max: u64,
        ctx: &mut TxContext,
    ) {
        if (compare<X, Y>()) {
            let pool = ofield::borrow_mut<String, LiquidityPool<X, Y>>(&mut lps.id, get_lp_name<X, Y>());
            let amount_in = get_amounts_in<X, Y>(pool, amount_out, true);
            assert!(amount_in <= amount_in_max, ERR_INSUFFICIENT_INPUT_AMOUNT);
            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (zero, coins_out) = swap_coins_for_coins<X, Y>(pool, coins_in, coin::zero(ctx), ctx);
            coin::destroy_zero(zero);
            return_remaining_coin(coins_in_origin, ctx);
            transfer::transfer(coins_out, tx_context::sender(ctx));
        } else {
            let pool = ofield::borrow_mut<String, LiquidityPool<Y, X>>(&mut lps.id, get_lp_name<Y, X>());
            let amount_in = get_amounts_in<Y, X>(pool, amount_out, false);
            assert!(amount_in <= amount_in_max, ERR_INSUFFICIENT_INPUT_AMOUNT);
            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (coins_out, zero) = swap_coins_for_coins<Y, X>(pool, coin::zero(ctx), coins_in, ctx);
            coin::destroy_zero(zero);
            return_remaining_coin(coins_in_origin, ctx);
            transfer::transfer(coins_out, tx_context::sender(ctx));
        }
    }

    /// swap from Coin to Coin, both sides
    /// require X < Y
    public fun swap_coins_for_coins<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_x_in: Coin<X>,
        coins_y_in: Coin<Y>,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        let (balance_x_out, balance_y_out)=
            swap_balance_for_balance<X, Y>(pool, coin::into_balance<X>(coins_x_in), coin::into_balance<Y>(coins_y_in));
        (coin::from_balance<X>(balance_x_out, ctx), coin::from_balance<Y>(balance_y_out, ctx))
    }

    /// swap from Balance to Balance, both sides
    /// require X < Y
    public fun swap_balance_for_balance<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_x_in: Balance<X>,
        coins_y_in: Balance<Y>,
    ): (Balance<X>, Balance<Y>) {
        let amount_x_in = balance::value(&coins_x_in);
        let amount_y_in = balance::value(&coins_y_in);
        assert!((amount_x_in > 0 && amount_y_in == 0) || (amount_x_in == 0 || amount_x_in > 0), ERR_INPUT_VALUE);
        if (amount_x_in > 0) {
            let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
            let amount_out = get_amount_out(amount_x_in, reserve_in, reserve_out, 0);
            swap<X, Y>(pool, coins_x_in, 0, coins_y_in, amount_out)
        } else {
            let (reserve_out, reserve_in) = get_reserves_size<X, Y>(pool);
            let amount_out = get_amount_out(amount_y_in, reserve_in, reserve_out, 0);
            swap<X, Y>(pool, coins_x_in, amount_out, coins_y_in, 0)
        }
    }

    /// Swap coins, both sides
    /// require X < Y
    public fun swap<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_x_in: Balance<X>,
        amount_x_out: u64,
        coins_y_in: Balance<Y>,
        amount_y_out: u64,
    ): (Balance<X>, Balance<Y>) {
        let amount_x_in = balance::value(&coins_x_in);
        let amount_y_in = balance::value(&coins_y_in);
        assert!(amount_x_in > 0 || amount_y_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(amount_x_out > 0 || amount_y_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        balance::join<X>(&mut pool.coin_x_reserve, coins_x_in);
        balance::join<Y>(&mut pool.coin_y_reserve, coins_y_in);
        let coins_x_out = balance::split(&mut pool.coin_x_reserve, amount_x_out);
        let coins_y_out = balance::split(&mut pool.coin_y_reserve, amount_y_out);
        // TODO assert_k_increase
        (coins_x_out, coins_y_out)
    }

    /// mint lp
    /// require X < Y
    public fun mint<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        _admin_data: AdminData,
        coin_x: Balance<X>,
        coin_y: Balance<Y>,
    ): Balance<LPCoin<X, Y>> {
        let amount_x = balance::value(&coin_x);
        let amount_y = balance::value(&coin_y);
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        let total_supply = balance::supply_value<LPCoin<X, Y>>(&pool.lp_supply);
        balance::join<X>(&mut pool.coin_x_reserve, coin_x);
        balance::join<Y>(&mut pool.coin_y_reserve, coin_y);
        let liquidity;
        if (total_supply == 0) {
            liquidity = sqrt(amount_x, amount_y) - MINIMUM_LIQUIDITY;
            let balance_reserve = balance::increase_supply(&mut pool.lp_supply, MINIMUM_LIQUIDITY);
            balance::join(&mut pool.lp_coin_reserve, balance_reserve);
        } else {
            let amount_1 = ((amount_x as u128) * (total_supply as u128) / (reserve_x as u128) as u64);
            let amount_2 = ((amount_y as u128) * (total_supply as u128) / (reserve_y as u128) as u64);
            liquidity = math::min(amount_1, amount_2);
        };
        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY_MINT);
        let coins = balance::increase_supply(&mut pool.lp_supply, liquidity);
        coins
    }

    /// burn lp
    /// require X < Y
    public fun burn<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        _admin_data: AdminData,
        liquidity: Balance<LPCoin<X, Y>>,
    ): (Balance<X>, Balance<Y>) {
        let liquidity_amount = balance::value(&liquidity);
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        let total_supply = balance::supply_value<LPCoin<X, Y>>(&pool.lp_supply);
        let amount_x = ((liquidity_amount as u128) * (reserve_x as u128) / (total_supply as u128) as u64);
        let amount_y = ((liquidity_amount as u128) * (reserve_y as u128) / (total_supply as u128) as u64);
        let x_coin_to_return = balance::split(&mut pool.coin_x_reserve, amount_x);
        let y_coin_to_return = balance::split(&mut pool.coin_y_reserve, amount_y);
        balance::decrease_supply(&mut pool.lp_supply, liquidity);
        (x_coin_to_return, y_coin_to_return)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}

#[test_only]
module defi::animeswap_tests {
    use sui::coin::{mint_for_testing as mint, destroy_for_testing as burn};
    // use sui::balance::{Self};
    use sui::coin::{Self};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use defi::animeswap::{Self, LiquidityPools, LPCoin};
    // use std::debug;

    const TEST_ERROR: u64 = 10000;

    /// Gonna be our test token.
    struct TestCoin1 has drop {}
    struct TestCoin2 has drop {}

    #[test]
    fun test_add_remove_lp_basic() {
        let scenario = scenario();
        let (owner, one, two) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            animeswap::init_for_testing(ctx(test));
        };
        next_tx(&mut scenario, two);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(&mut lps, ctx(test));
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                &mut lps,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );
            assert!(burn(lp_coins) == 9000, TEST_ERROR);
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                &mut lps,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );

            assert!(burn(lp_coins) == 10000, TEST_ERROR);
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let (coin_x, coin_y) = animeswap::remove_liquidity<TestCoin1, TestCoin2>(
                &mut lps,
                mint<LPCoin<TestCoin1, TestCoin2>>(1000, ctx(test)),
                500,
                1,
                1,
                ctx(test),
            );

            assert!(burn(coin_x) == 500, TEST_ERROR);
            assert!(burn(coin_y) == 500, TEST_ERROR);
            test::return_shared(lps);
        };
        test::end(scenario);
    }

    #[test]
    fun test_swap_lp_basic() {
        let scenario = scenario();
        let (owner, one, _) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            animeswap::init_for_testing(ctx(test));
        };
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(&mut lps, ctx(test));
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                &mut lps,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );
            assert!(burn(lp_coins) == 9000, TEST_ERROR);
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let (pool_mut, _admin_data) = animeswap::get_pool<TestCoin1, TestCoin2>(&mut lps);
            let (zero, coins_out) = animeswap::swap_coins_for_coins<TestCoin1, TestCoin2>(
                pool_mut,
                mint<TestCoin1>(1000, ctx(test)),
                coin::zero(ctx(test)),
                ctx(test),
            );
            coin::destroy_zero(zero);
            assert!(burn(coins_out) == 909, TEST_ERROR);
            test::return_shared(lps);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            let (pool_mut, _admin_data) = animeswap::get_pool<TestCoin1, TestCoin2>(&mut lps);
            let (coins_out, zero) = animeswap::swap_coins_for_coins<TestCoin1, TestCoin2>(
                pool_mut,
                coin::zero(ctx(test)),
                mint<TestCoin2>(1000, ctx(test)),
                ctx(test),
            );
            coin::destroy_zero(zero);
            assert!(burn(coins_out) == 1090, TEST_ERROR);
            test::return_shared(lps);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = animeswap::ERR_PAIR_ALREADY_EXIST)]
    fun test_create_lp_dup_error() {
        let scenario = scenario();
        let (owner, one, two) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            animeswap::init_for_testing(ctx(test));
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(&mut lps, ctx(test));
            test::return_shared(lps);
        };
        next_tx(&mut scenario, two);
        {
            let test = &mut scenario;
            let lps = test::take_shared<LiquidityPools>(test);
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(&mut lps, ctx(test));
            test::return_shared(lps);
        };
        test::end(scenario);
    }

    // utilities
    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address, address) { (@0xBEEF, @0x1111, @0x2222) }
}
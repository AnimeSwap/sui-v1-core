module defi::animeswap {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin, TreasuryCap};
    use std::option;
    // use sui::balance::{Self, Supply, Balance};
    // use sui::sui::SUI;
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};

    /// When contract error
    const ERR_INTERNAL_ERROR: u64 = 102;
    /// When not enough X amount
    const ERR_INSUFFICIENT_X_AMOUNT: u64 = 108;
    /// When not enough Y amount
    const ERR_INSUFFICIENT_Y_AMOUNT: u64 = 109;
    /// When not enough amount for pool
    const ERR_INSUFFICIENT_AMOUNT: u64 = 201;
    /// When not enough liquidity amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 202;

    struct LPCoin<phantom X, phantom Y> has drop {}

    struct LiquidityPool<phantom X, phantom Y> has key {
        id: UID,
        coin_x_reserve: Coin<X>,
        coin_y_reserve: Coin<Y>,
        cap: TreasuryCap<LPCoin<X, Y>>,
    }

    /// given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    public fun quote(
        amount_x: u64,
        reserve_x: u64,
        reserve_y: u64
    ):u64 {
        assert!(amount_x > 0, ERR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_y = ((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128) as u64);
        amount_y
    }

    /// Calculate optimal amounts of coins to add
    public fun calc_optimal_coin_values<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ): (u64, u64) {
        let (reserve_x, reserve_y) = (coin::value(&pool.coin_x_reserve), coin::value(&pool.coin_y_reserve));
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

    entry fun create_pair_entry<X, Y>(
        ctx: &mut TxContext,
    ) {
        let (treasury_cap, metadata) = coin::create_currency<LPCoin<X, Y>>(LPCoin<X, Y>{}, 8, b"ANILPCoin", b"AnimeSwapLPCoin", b"", option::none(), ctx);
        transfer::freeze_object(metadata);
        transfer::share_object(LiquidityPool<X, Y> {
            id: object::new(ctx),
            coin_x_reserve: coin::zero<X>(ctx),
            coin_y_reserve: coin::zero<Y>(ctx),
            cap: treasury_cap,
        });
    }

    entry fun add_liquidity_entry<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_x_origin: Coin<X>,
        coin_y_origin: Coin<Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ) {
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

        let (amount_x, amount_y) = calc_optimal_coin_values<X, Y>(pool, amount_x_desired, amount_y_desired, amount_x_min, amount_y_min);
        let coin_x = coin::take<X>(coin::balance_mut<X>(&mut coin_x_origin), amount_x, ctx);
        let coin_y = coin::take<Y>(coin::balance_mut<Y>(&mut coin_y_origin), amount_y, ctx);
        let lp_coins = mint<X, Y>(pool, coin_x, coin_y, ctx);
        transfer::transfer(coin_x_origin, tx_context::sender(ctx));
        transfer::transfer(coin_y_origin, tx_context::sender(ctx));
        transfer::transfer(lp_coins, tx_context::sender(ctx));
    }

    public fun mint<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        ctx: &mut TxContext,
    ): Coin<LPCoin<X, Y>> {
        let amount_x = coin::value(&coin_x);
        let amount_y = coin::value(&coin_y);
        coin::join<X>(&mut pool.coin_x_reserve, coin_x);
        coin::join<Y>(&mut pool.coin_y_reserve, coin_y);
        let liquidity = math::sqrt(amount_x) * math::sqrt(amount_y);
        coin::mint<LPCoin<X, Y>>(&mut pool.cap, liquidity, ctx)
    }
}

#[test_only]
module defi::animeswap_tests {
    
}
module defi::animeswap_library {
    use sui::math;

    /// When not enough amount for pool
    const ERR_INSUFFICIENT_AMOUNT: u64 = 201;
    /// When not enough liquidity amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 202;
    /// When not enough input amount
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 203;
    /// When not enough output amount
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 204;
    /// When two coin type is the same
    const ERR_COIN_TYPE_SAME_ERROR: u64 = 205;

    /// given some amount of an asset and pair reserves,
    /// returns an equivalent amount of the other asset.
    public fun quote(
        amount_x: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u64 {
        assert!(amount_x > 0, ERR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_y = ((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128) as u64);
        amount_y
    }

    /// given an input amount of an asset and pair reserves,
    /// returns the maximum output amount of the other asset.
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ): u64 {
        assert!(amount_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_in_with_fee = (amount_in as u128) * ((10000 - swap_fee) as u128);
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * 10000 + amount_in_with_fee;
        let amount_out = numerator / denominator;
        (amount_out as u64)
    }

    /// given an output amount of an asset and pair reserves,
    /// returns a required input amount of the other asset
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ): u64 {
        assert!(amount_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let numerator = (reserve_in as u128) * (amount_out as u128) * 10000;
        let denominator = ((reserve_out - amount_out) as u128) * ((10000 - swap_fee) as u128);
        let amount_in = numerator / denominator + 1;
        (amount_in as u64)
    }

    public fun sqrt(x: u64, y: u64): u64 {
        (math::sqrt_u128((x as u128) * (y as u128)) as u64)
    }
}
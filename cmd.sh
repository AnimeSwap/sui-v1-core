sui client publish --gas-budget 10000

sui client call \
--package 0x64efde85679fbddf7a58af549d91cc673f22676b \
--module animeswap \
--function create_pair_entry \
--gas-budget 10000 \
--type-args \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin1::TESTCOIN1 \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin2::TESTCOIN2

sui client call \
--package 0x64efde85679fbddf7a58af549d91cc673f22676b \
--module animeswap \
--function add_liquidity_entry \
--gas-budget 10000 \
--type-args \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin1::TESTCOIN1 \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin2::TESTCOIN2 \
--args \
0x9d4982c09fcc71f135ae20a08aca327e2012f57a \
0xcca14742a60a1b97d6ea3b8dc2cd73c631eaa49a \
0xbc26538ea47a7b3cb02dcb57fb97dac325aadcbe \
1000000000000 1000000000000 1 1

sui client call \
--package 0x64efde85679fbddf7a58af549d91cc673f22676b \
--module animeswap \
--function swap_exact_coins_for_coins \
--gas-budget 10000 \
--type-args \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin1::TESTCOIN1 \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin2::TESTCOIN2 \
--args \
0x9d4982c09fcc71f135ae20a08aca327e2012f57a \
0xcca14742a60a1b97d6ea3b8dc2cd73c631eaa49a \
500000000000 1

sui client call \
--package 0x64efde85679fbddf7a58af549d91cc673f22676b \
--module animeswap \
--function swap_coins_for_exact_coins \
--gas-budget 10000 \
--type-args \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin2::TESTCOIN2 \
0xcdc0854bab85989b55d06dc7a5d0e757f053cd98::testcoin1::TESTCOIN1 \
--args \
0x9d4982c09fcc71f135ae20a08aca327e2012f57a \
0xbc26538ea47a7b3cb02dcb57fb97dac325aadcbe \
250000000000 1000000000000
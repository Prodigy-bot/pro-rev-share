# Prodigy Bot Revenue Share

Smart contract that manages revenue share for the Prodigy Bot.

Users must stake tokens in order to participate. The contract receives ETH and stores how much per token you get.

## Testing

Tests are written using Foundry. You can run them with the command `forge test`.

The UniswapMock contract allows you to etch the mainnet Uniswap V2 contract bytecode straight into a local chain for testing without forks.

## Coverage

You need `lcov` installed to run the test coverage script.

Run with `sh coverage.sh`.

After running it you will find it on a folder called `coverage` in the root.

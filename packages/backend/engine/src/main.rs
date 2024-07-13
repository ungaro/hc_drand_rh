use dotenv::dotenv;
use eyre::Result;
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::Arc, time::Duration};
use tokio::time;

use alloy::{
    network::EthereumWallet, 
    node_bindings::Anvil, 
    primitives::{Address,address, U256},
    providers::{Provider, ProviderBuilder,WsConnect},
    signers::local::PrivateKeySigner, 
    sol,
    transports::http::{Client, Http},

};


sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    DrandOracle,
    "abi/IDrandOracle.json"
);

sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    SequencerRandomOracle,
    "abi/ISequencerRandomOracle.json"
);

sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    RandomnessOracle,
    "abi/IRandomnessOracle.json"
);


#[derive(Debug, Serialize, Deserialize)]
struct DrandResponse {
    round: u64,
    randomness: String,
    signature: String,
}

#[derive(Debug)]
enum QueuedTransaction {
    Drand { timestamp: u64, value: String },
    Commitment { timestamp: u64, value: String },
    Reveal { timestamp: u64, value: String },
}

struct RandomOracleService {
    public_client: Arc<Provider<Http>>,
    wallet: EthereumWallet,
    drand_oracle: DrandOracle<Provider<Http>>,
    sequencer_random_oracle: SequencerRandomOracle<Provider<Http>>,
    randomness_oracle: RandomnessOracle<Provider<Http>>,
    transaction_queue: Vec<QueuedTransaction>,
    sequencer_randomness_cache: HashMap<u64, String>,
    processed_drand_timestamps: std::collections::HashSet<u64>,
}

impl RandomOracleService {
    async fn new() -> Result<Self> {
        dotenv().ok();
        
        let rpc_url = std::env::var("RPC_URL").expect("RPC_URL must be set");
        let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY must be set");
        
//        let provider = Provider::<Http>::try_from(rpc_url)?;


    // Create the provider.
    let ws = WsConnect::new(rpc_url.parse()?);
    let provider = ProviderBuilder::new().on_ws(ws).await?;

        //let provider = ProviderBuilder::new().on_http(rpc_url.parse()?);


        //let wallet: LocalWallet = private_key.parse()?;
        
        //let signer: PrivateKeySigner = anvil.keys()[0].clone().into();
        let wallet = EthereumWallet::from(private_key.parse()?);



        let drand_oracle_address: Address = std::env::var("DRAND_ORACLE_ADDRESS")?.parse()?;
        let sequencer_random_oracle_address: Address = std::env::var("SEQUENCER_RANDOM_ORACLE_ADDRESS")?.parse()?;
        let randomness_oracle_address: Address = std::env::var("RANDOMNESS_ORACLE_ADDRESS")?.parse()?;
        
        Ok(Self {
            public_client: Arc::new(provider.clone()),
            wallet,
            drand_oracle: DrandOracle::new(drand_oracle_address, Arc::new(provider.clone())),
            sequencer_random_oracle: SequencerRandomOracle::new(sequencer_random_oracle_address, Arc::new(provider.clone())),
            randomness_oracle: RandomnessOracle::new(randomness_oracle_address, Arc::new(provider)),
            transaction_queue: Vec::new(),
            sequencer_randomness_cache: HashMap::new(),
            processed_drand_timestamps: std::collections::HashSet::new(),
        })
    }

    async fn run(&mut self) -> Result<()> {
        let mut interval = time::interval(Duration::from_secs(1));
        
        loop {
            interval.tick().await;
            
            self.backfill_missing_values().await?;
            let block = self.public_client.get_block_number().await?;
            let timestamp = self.public_client.get_block_timestamp(block).await?;
            self.backfill_sequencer_values(timestamp).await?;
            self.process_pending_transactions().await?;
            self.process_sequencer_reveals(timestamp).await?;
        }
    }

    async fn backfill_missing_values(&mut self) -> Result<()> {
        // Implementation here
        Ok(())
    }

    async fn backfill_sequencer_values(&mut self, current_timestamp: u64) -> Result<()> {
        // Implementation here
        Ok(())
    }

    async fn process_pending_transactions(&mut self) -> Result<()> {
        // Implementation here
        Ok(())
    }

    async fn process_sequencer_reveals(&mut self, current_timestamp: u64) -> Result<()> {
        // Implementation here
        Ok(())
    }

    // Add other methods here...
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    
    let mut service = RandomOracleService::new().await?;
    service.run().await
}

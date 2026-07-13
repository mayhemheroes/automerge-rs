#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: Vec<&[u8]>| {
    let mut ac = automerge::AutoCommit::default();
    for update in data {
        let _ = ac.load_incremental(update);
    }
});

module poc::poc;

public struct Marker has key { id: UID, n: u64 }

public fun mint(ctx: &mut TxContext) {
    transfer::transfer(Marker { id: object::new(ctx), n: 1 }, ctx.sender());
}

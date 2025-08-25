fn main() {
    println!("cargo:rerun-if-changed=wit");
    wit_bindgen::generate!({
        world: "counter-world",
        path: "./wit",
        out_dir: "src",
    });
}
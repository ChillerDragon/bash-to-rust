# bash to rust

THIS IS A JOKE PROJECT! LOOK ELSEWHERE FOR USEUFUL STUFF!

So the idea is that it can take bash code and transpile it into rust code. Sounds cool huh?


... but I am not even trying to make it any good so it will be a mess of a codebase and never reach a useful state. Do not get your hopes up.
To see the pathetic progress check the transpile_tests/ folder. All those shell scripts should be convertable if the CI passes.


## Sample

Input:
```bash
#!/bin/bash

mystr="hello world"
echo "$mystr"
```

Output:
```rust
fn main() {
// !/bin/bash
let mystr = String::from("hello world");
println!("{}", mystr);
}
```

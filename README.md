# Zig LC3 Virtual Machine

An LC3 virtual machine written in zig, created by following [jmeiners amazing tutorial](https://www.jmeiners.com/lc3-vm/).

> [!important]
> Uses the development 0.16 version of zig, as of writing what exists in [main](https://www.jmeiners.com/lc3-vm/#memory-mapped-registers)

This project was mostly an excuse to use zig. I have read the documentation a few times and needed a meaty project to play with it. Most of my commentary will be on zig as a language and not so much on the tutorial. However this is a great "first project" with a new language as it forces you to go a bit deeper.

Given that, this code likely sucks! I hope I did the zig world a bit proud with a first project, but I doubt it. With that said I love the language and will be diving deeper.

## Take Aways

- Ensure you use the `+%` or [@addWithOverflow](https://ziglang.org/documentation/master/#addWithOverflow)
- [Remember to flush](https://ziggit.dev/t/systems-distributed-dont-forget-to-flush/11431)
- The new [juicy main](https://codeberg.org/ziglang/zig/pulls/30644) feature is really powerful.
- The new [readers and writers](https://zig.guide/standard-library/readers-and-writers/) in `15.1` and the [upcoming changes](https://codeberg.org/ziglang/zig/pulls/30232) to `Io` in `0.16` seem like a great improvement.
- [Intrusive Interfaces](https://youtu.be/oVHarxAoQrY?si=tCEYcjdNVPwQLvkq) are neat, and now I have a new [youtubers](https://www.youtube.com/@ComputerBread) backlog to consume!


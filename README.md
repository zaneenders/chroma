# Chroma

> Taking control of the screen.

Chroma is a user interface (UI) framework, currently focused on terminal-based applications for developers, encouraging the mindset to build your own digital experience, and sharing components with others so that we can all take control of our screens and the data that they reflect.

**Problem:** The current application model of how we use computers, sandboxing, and categorizing approach introduces many inconsistencies and is labor-intensive software to write and maintain, as each application developer(s) has to uphold their own visual abstraction alongside the host operating system’s own decisions about how UI should be represented. Creating a complex moving problem leaving users with inconsistent UI between their various applications and growing assumed knowledge, slow cross-platform solutions in our accelerating fast-paced world. To get work done you often find yourself juggling between multiple applications often running into inconsistency between them and spending more time moving between tasks than actual work needed to be done. In addition to this developers have to avoid or be very careful about moving where features live on the screen because the abstraction is the only interface for the user and if you move stuff around on them it becomes disorienting.

**Solution:** Chroma solves these problems by making a few observations about UI in general. First, all UI has some notion of selection for the system to understand what the user is interacting with. The second UI is often modeled as a tree structure. The document object model (DOM) used by the web browser is the most used way to represent UI. This nested tree-like structure is apparent in other UI frameworks as well. Chroma reduces the kinds of nodes that these trees can be constructed with down to groupings of groups and characters with optional modifiers for layout control and modifying state.

Chroma also restricts the method of how you interact with the screen to keyboard-based commands. This is an artificial restriction with plans to bring back other forms of input down the road. However, the popularity of keyboard-only based text editors like [vim](https://www.vim.org) and [emacs](https://www.gnu.org/software/emacs/) suggest that the mouse might not be needed if Chroma's approach has an easier learning curve and can show to be more efficient in user time spent getting work done. Only six commands are needed as a base input language to navigate and interact with the UI. At base implementation this is a bit cumbersome to use so optimizations are being added to reshape and flatten the tree alongside an input reply feature for UI-level macros alongside allowing other input bindings for quick access to desired functionality.

Chroma aims to fundamentally invert the traditional application model. Imagine a single, unified text editor for all text fields across your system, a consistent visual design language, and a navigation paradigm that spans all the domains in which you use your computer. Chroma empowers developers to build and share their creations and solutions as UI components, easily allowing for context-sensitive extensions. Encouraging end-user-defined abstractions for a personalized digital experience. Building a consistent interface for navigating and interacting with the screen.

Actions are stronger than words so I strongly encourage giving the demo a try.

**Inspiration**

SwiftUI, spreadsheet applications, video games, and keyboard-based text editors like vim and emacs.

## Running the Demo

### Locally

If you have Swift 6.0 or later installed for MacOS and Linux you can run the demo locally.

```sh
swift run
```

If anyone wants to brave Swift on [Windows](https://www.swift.org/install/windows/) I think adding support for Windows and Powershell shouldn’t be too bad…

### Docker

Run the demo in an interactive Docker image.

```sh
docker build -t chroma:latest .
docker run -it chroma:latest
```

> Note: This builds and runs the demo using the [Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html) and runs the executable in a [`From scratch`](https://hub.docker.com/_/scratch) Docker image. This creates an accessible, low-dependency environment in which to test out Chroma. So the first build will take a minute well the SDK is downloaded and installed. This demonstrates that Chroma could run directly on the Linux kernel. In the long term, the goal is to provide Chroma as an alternative to a system shell for interacting with the kernel and managing system resources.

## Exploring the Demo

The demo provides a basic exploration of Chroma's current capabilities.

To explore the demo, run it as described [above](/README.md#running-the-demo). Once it’s running, you’ll see a white text with a purple background displayed in your terminal. Here are some instructions to get started with:

1. **Hand placement** Key your hands on the home row like you would for writing a document.
1. **Move into the tree:** Press the `l` key once. This moves your focus into the binding within the tree.
1. **Trigger a Binding:** Press the `i` key. This will trigger the associated action, which appends characters to two separate strings.
1. **Move Down:** Press the `j` key twice to another binding.
1. **Trigger a async Task:** Press the `i` key. This binding simulates calling an async function required to do a non-blocking load of file into memory or a network call to an API.
1. **Move Up:** Press the `f` key to move back up the tree.
1. **Trigger the last Binding:** Press the `e` key or hold it down to increment the counter.
1. **Move Out:** Press the `f` key to move back up the tree.

Try experimenting with these commands to explore the different bindings and actions in the demo.

For ideas on modifying the demo and exploring other tree structures, see the [Demo.swift](/Sources/Demo/Demo.swift) and [BlockSnippets.swift](/Sources/Demo/BlockSnippets.swift) files. These movements navigate the tree structure produced by the [`@resultBuilder`](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#resultBuilder) [parser](/Sources/Chroma/DSL/BlockParser.swift).

> Note: Drawing attention to the second binding we explored displayed below, is an example of triggering an async UI update. The UI is updated on the main thread via the `@MainActor` Swift API. But the work behind an async call like this could be on other threads allowing the UI to stay interactive. You can read more about how Swift handles concurrency [here](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/).

```swift
"Job running: \(running)".bind { selected, key in
  if selected && key == .lowercaseI {
    self.longRunningTask()
  }
}
```

## Documentation

View the [DocC](https://www.swift.org/documentation/docc) documentation:

```sh
swift package --disable-sandbox preview-documentation --target Chroma
```

This builds the documentation and starts a server on [localhost](http://localhost:8080/documentation/chroma).

## Road Map

Here are some of the planned upcoming APIs for the project.

### 0.0.1 Release Goals

- [x] Optimize tree Navigation: Improve performance through flattening and structural control.
- [x] Implement Modal Input: Enable context-specific interactions like text input and custom modes.
- [x] Customizable Keybindings: Allow users to personalize movement and actions.
- [ ] Basic Color Support: Add foreground and background colors using ANSI escape codes.
- [ ] Horizontal Layout: Provide more flexible UI design language.
- [ ] (Bonus) Z-Axis Layering: Enable modal windows as a possible input prompt.

These features will provide the building blocks for tools to interact with the file system and running shell commands, moving towards more complex user interfaces like a text editor.

## Additional Notes

Chroma is under active development. Feedback is welcome. Please open an [issue](https://github.com/zaneenders/chroma/issues) to share your thoughts.

Thanks,
Zane
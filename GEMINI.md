# Ralph Wiggum Loop Extension for Gemini CLI

This document provides persistent context to the Gemini model when using the Ralph Wiggum Loop extension.

## Overview

The Ralph Wiggum Loop is a Gemini CLI extension designed to create a self-referential, iterative development workflow. Once activated, it will repeatedly present the model with the same initial prompt, allowing for continuous refinement and iteration on a task without manual re-prompting. The loop continues until a specific completion promise is met or a maximum number of iterations is reached.

## Features

-   **Persistent State:** Loop parameters (prompt, iteration, limits) are stored in `.gemini/ralph-loop.json`.
-   **Iterative Prompting:** The original prompt is automatically re-fed to the model in subsequent turns.
-   **Completion Promise:** Define a specific text phrase that, when output by the model, signals the completion of the task and terminates the loop.
-   **Max Iterations:** Set an optional limit to the number of iterations to prevent infinite loops.
-   **User Interjection:** The loop gracefully handles user interruptions, pausing for one turn to address user input before automatically resuming the loop.

## Usage

The loop is controlled via custom commands:

-   **`/ralph:loop [PROMPT...] [--max-iterations N] [--completion-promise TEXT]`**: Starts a new Ralph loop with the given initial prompt and optional parameters.
-   **`/ralph:cancel`**: Manually stops an active Ralph loop.

## How it Works (Technical Details)

This extension utilizes Gemini CLI's powerful hook system:

-   **`AfterAgent` Hook (Controller):** Runs after each agent turn to evaluate termination conditions (completion promise, max iterations) and determine if the loop should continue. If so, it signals the `BeforeAgent` hook.
-   **`BeforeAgent` Hook (Injector):** Runs before each agent turn. If signaled by the `AfterAgent` hook, it injects the original loop prompt back into the model's context for the upcoming turn.
-   **Inter-Hook Communication:** A temporary file (`.gemini/ralph-reprompt.tmp`) is used to pass the prompt from the `AfterAgent` (Controller) to the `BeforeAgent` (Injector).

---
**Note:** For the loop to function, hooks must be enabled in your Gemini CLI settings. Refer to the official Gemini CLI documentation for details on enabling hooks.

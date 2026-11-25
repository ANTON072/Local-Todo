---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet.

Ask **one question at a time**. From the frontier, pick the question that unblocks the most of the tree (the most upstream one), ask only that, give your recommended answer, and wait for the user's answer before asking the next. Never batch several questions into one message, even when several are on the frontier. Number questions sequentially across the whole session (Q1, Q2, …).

Format a question like so:

```
❓ **Q<n>** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each answer reshapes the tree: a settled decision pushes the frontier outward and unblocks questions that depended on it, and may make questions you had in mind unnecessary. Recompute the frontier after every answer and pick the next question from it.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so ask a question that doesn't depend on it while it runs. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

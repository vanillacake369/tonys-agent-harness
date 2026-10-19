---
name: skl-post-blog-ljh
description: Phase-gated Korean technical blog writing with source-aware tone, sample approval, and structure validation.
---

# Korean Technical Blog Workflow

Use this skill when the user asks to write, refine, or structure a Korean
technical blog post.

The workflow is conversational and phase-gated. Do not skip a phase because
the topic appears familiar. Do not write the final file before the user
explicitly approves the sample and confirms the output path.

## Phase 1 — Specification checklist

Ask and record:

- topic and central question;
- intended reader;
- source material and official or original references;
- whether a Why section already exists;
- coverage: full topic, focused topic, or series;
- implementation depth: overview, definitions, or key functions;
- background depth;
- personal-experience scope and anonymization requirements;
- citation and footnote preference;
- desired output path and template;
- whether the post should contain code, tables, Mermaid, or experiments.

Keep the user's answers as the working specification. Mark unknown facts as
unverified instead of filling them with plausible details.

## Phase 2 — Narrative skeleton and TOC

Before drafting, propose:

1. one question that governs the whole post;
2. the tension and resolution of each major section;
3. the reason each section leads to the next;
4. a detailed table of contents;
5. the placement of code, tables, Mermaid, examples, and references;
6. the expected length and whether splitting is necessary.

Use an outside-in order. Start with an observable problem or workflow, then
introduce the concept required to explain it, then show the implementation or
operational decision.

Avoid a keyword catalogue. A section should move from problem to mechanism to
decision to verification.

## Phase 3 — Scope and length

Confirm:

- coverage;
- technical depth;
- background depth;
- single file or series;
- expected length;
- verification method.

If the estimated post is longer than 1,500 lines or contains independent
domains, propose a split and wait for the user's choice.

## Phase 4 — Sample section

Write one representative section slice only. It must demonstrate the chosen
tone, heading hierarchy, paragraph length, tables, code or Mermaid placement,
and citation style.

Wait for explicit approval before writing the full post. Accepted signals
include “진행해줘”, “이대로 OK”, “전체 본문 작성”, and “통과”.

## Phase 5 — Final writing

After approval and output-path confirmation, write the full post in the
approved template.

Use this document structure unless the user explicitly chooses another one:

    # WHY

    # WHAT

    ## General problem or concept
    ### Concrete mechanism
    #### Example, exception, or verification

    # HOW

    ## Applying it to my situation
    ### Current state
    #### Personal example or decision

    # REMARK

    # REFERENCE

WHAT must not contain the user's personal experience. Use general developer
experiences, public research, broadly applicable operational patterns, or
clearly marked special cases instead.

HOW is where the user's situation may first appear. Keep company, team,
person, repository, account, IP, internal URL, channel, and credential details
anonymous unless the user explicitly authorizes their publication.

REMARK contains personal reflection, operational judgement, sustainability
assessment, and the conditions for continuing or changing direction.

## Voice and formatting

- Use consistent Korean declarative prose: 다/이다/한다.
- Use an analytical white-paper voice with slightly expanded prose.
- Keep one idea per paragraph, normally two to five sentences.
- Avoid sensory metaphors, compressed aphorisms, rhetorical overstatement,
  hedging, audience address, and unnecessary asides.
- Avoid first person in WHAT. First person is allowed in WHY only when the
  user explicitly requests a personal introduction, and in HOW or REMARK for
  the approved personal application.
- Do not use emojis in headings or body text.
- Do not use English concept names as the first words of H2 headings when a
  natural Korean sentence is available.
- Keep WHAT/HOW as H1 sections. Start each major subsection at H2, then use
  H3, H4, and H5 for narrower scope.
- Use tables for comparisons and Mermaid for direction, sequence, hierarchy,
  or state transitions. Explain every Mermaid diagram in prose immediately
  afterward.
- Introduce a concept when it is needed to solve the preceding problem, not
  as an isolated dictionary definition.
- Pair each mechanism with when it is used, what decision it supports, or what
  trade-off it creates.
- Use GitHub Alert blocks only when an important term or operational warning
  cannot be explained in one sentence.

## Personal application pattern

For a post about work motivation, automation, or operational improvement, use
the following progression when relevant:

1. describe the general problem without the user's story;
2. explain autonomy, mastery, purpose, or the relevant domain concepts;
3. apply the concepts to the user's current work;
4. identify a small improvement or experiment;
5. separate personal control from organizational decisions;

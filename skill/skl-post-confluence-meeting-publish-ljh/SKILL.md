---
name: skl-post-confluence-meeting-publish-ljh
description: Publish finalized meeting minutes as a new Confluence page under an authorized parent and verify the saved page. Use after drafting or reviewing the minutes.
metadata:
  kind: skill
  behavior: not-verified
---

# Skill / Publish Meeting Minutes to Confluence

Use the finalized minutes, the meeting date and type, and the Confluence destination supplied by the user or a private team workflow. The publication scope must cover the specific destination. Keep organization-specific destinations in the private workflow.

1. Use the authenticated Atlassian tool to resolve the parent. Confirm its ID, space, type and applicable year. List its direct children, following pagination, and use the team's existing title convention if the caller has not supplied one. Check for the same date and meeting type under the parent. If a match exists, return its link. Report title conflicts or ambiguous matches before creating another page.
2. Read any applicable Confluence space instructions and the page authoring guides required by the tool. Publish the finalized body with its headings, lists, links, decisions and open questions intact. Use the page title once and omit source transcripts and drafting notes.
3. Create a published page under the verified parent, using the authenticated tool's supported parent parameter. If a write returns an uncertain result, look for the same meeting under that parent before any retry. Report a permission or authentication failure with the affected destination.
4. Read the saved page and confirm its title, published status, parent and key sections or links. Return the page URL. For multiple destinations, report the result for each so a retry can resume from the missing pages.

```json composition
{"requires": [], "hints": []}
```

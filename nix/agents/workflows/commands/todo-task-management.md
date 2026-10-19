# Todo Task Management Workflow

Use this workflow when the user asks an agent to manage todo tasks through an
external MCP server such as TickTick.

## Operating Rules

1. Treat external todo data as user-owned state.
2. Read/search/list operations are allowed when they directly support the user's
   request.
3. Create, update, complete, archive, or delete tasks only when the user clearly
   asks for that mutation.
4. Before bulk mutations, destructive changes, or ambiguous completion actions,
   show the candidate task list and get explicit confirmation.
5. Before creating a new task, search for likely duplicates when the request
   includes a project, title, date, or tag that can identify an existing task.
6. Preserve user intent in task metadata: title, project/list, due date,
   timezone, priority, tags, notes, and recurrence.
7. If date or timezone is ambiguous, ask a short clarification before writing.
8. After mutation, summarize exactly what changed and mention any task that could
   not be found or updated.

## Default Flow

1. Identify whether the request is read-only or mutating.
2. For read-only requests, retrieve the smallest useful set of projects, lists,
   or tasks and answer from that evidence.
3. For a single clear mutation, perform the change and report the created or
   updated task.
4. For multiple or destructive mutations, present the planned changes first and
   wait for confirmation.
5. If the MCP server returns authentication or permission errors, stop and report
   the missing authorization without asking the user to paste secrets into chat.

# Apple Intelligence summary experiments

Tested on-device with greedy sampling and a 40-token response limit. Eight synthetic cases per prompt, 24 generations total. These are spot checks, not an accuracy guarantee.

## Decision

Retain complete-summary-v5. It preserved the important planned/completed/uncertain distinctions in these cases, but omitted the MIT recommendation and planned sign-in check in one case. The sign-in blocker summary was less explicit than its source. Both alternatives introduced unsupported next steps or changed completion state and were rejected.

Regression checks separately cover retaining the previous summary during generation, showing the replacement when ready, removing recovered errors, and retaining input-required status.

## Selected v5

```text
SOURCE: I will run the build tomorrow. No tests have run yet.
OUTPUT: Build scheduled for tomorrow; no tests executed.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; deployment not completed.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Missing file may explain unexplained failure.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Folder created; retry succeeded.
SOURCE: Sign-in is still blocked. I need the user to complete browser authentication before I can continue.
OUTPUT: User requires browser authentication before proceeding.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: License selection remains incomplete.
SOURCE: I am comparing the two exports. Several totals differ and I am still investigating.
OUTPUT: Totals differ; investigation ongoing.
SOURCE: The draft release was created successfully. It remains unpublished.
OUTPUT: Draft release created; remains unpublished.
```

## Rejected v6: stronger next-step instruction

```text
SOURCE: I will run the build tomorrow. No tests have run yet.
OUTPUT: Build scheduled; no tests executed yet.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; deployment not planned.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Planned check of missing file to diagnose failure.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Folder creation planned; retry succeeded.
SOURCE: Sign-in is still blocked. I need the user to complete browser authentication before I can continue.
OUTPUT: User sign-in blocked; browser authentication required.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: Planned check of GitHub sign-in for license selection.
SOURCE: I am comparing the two exports. Several totals differ and I am still investigating.
OUTPUT: Comparison of totals planned; investigation ongoing.
SOURCE: The draft release was created successfully. It remains unpublished.
OUTPUT: Draft release creation completed; publish action planned.
```

## Rejected v7: simplified instruction

```text
SOURCE: I will run the build tomorrow. No tests have run yet.
OUTPUT: Build scheduled for tomorrow; no tests completed yet. Next step: verify build readiness.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; app deployment remains incomplete.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Summary: Investigation of the missing file may explain the failure; confirmation needed.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Summary: Folder creation succeeded after initial failure; next step: verify folder access.
SOURCE: Sign-in is still blocked. I need the user to complete browser authentication before I can continue.
OUTPUT: Sign-in is blocked; user must complete browser authentication. Next step: verify user credentials.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: MIT recommended; license selection uncertain; check GitHub sign-in. Next step: confirm license selection.
SOURCE: I am comparing the two exports. Several totals differ and I am still investigating.
OUTPUT: Totals for 2024-Q1 and 2024-Q2 differ; investigation ongoing.
SOURCE: The draft release was created successfully. It remains unpublished.
OUTPUT: Draft release for "The Draft Release" created successfully; unpublished. Next step: publish.
```

## Latest-update follow-up

A real quality trace showed the latest message was present in a three-message batch, but the model summarised an earlier message. Input now contains only the latest message. Six further prompt candidates were tested against five cases each (30 generations). Selected latest-result-action-v13 preserved result-then-current-action in the reported example, plus deployment and uncertainty caveats. Recovery wording remains awkward and loses retry detail in this spot check; this is not a guarantee of semantic accuracy.

### v8

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: Completed: All 19 postage-related tests passed; Checking final layout in the app, including the new column and shared labels.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Completed: Build and regression tests passed; Next: App not deployed.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: Completed: MIT licence not selected;
Next: Check GitHub sign-in.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Completed: Folder created; Current: Retry succeeded.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Completed: Missing file may explain failure; Current: Cause not confirmed.
```

### v9

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: Change build succeeded; 19 postage-related tests passed. Final layout in app reviewed.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; app deployment not started.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: MIT recommended; GitHub sign-in check planned.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Folder missing was the cause; retry succeeded.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Missing file is a possible cause; diagnosis remains unconfirmed.
```

### v10

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: Change build succeeded; 19 postage-related tests passed; final layout review ongoing.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; deployment not yet occurred.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: MIT recommendation; licence selection pending; GitHub sign-in check planned; reviewing GitHub access.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Folder missing was the issue; retry succeeded; review ongoing.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Missing file is a possible cause; diagnosis remains unconfirmed. I am reviewing the error logs.
```

### v11

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: Change built; checking the final layout in the app.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build passed; verifying deployment readiness.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: License selection blocked; checking GitHub sign-in.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Folder created; retry succeeded.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Missing file flagged; investigating file status.
```

### v12

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: Change built successfully; 19 postage-related tests passed. Checking final layout in the app, including the new column and shared labels.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests (100/100) passed; app not deployed.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: License: MIT; Test count: 0; Action: Checking GitHub sign-in.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: Test 1: Folder missing; retry succeeded.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Test 1/1: Missing file detected; cause unconfirmed.
```

### v13

```text
SOURCE: The change builds successfully, and all 19 postage-related tests passed. I’m checking the final layout in the app, including the new column and how shared labels display.
OUTPUT: All 19 postage-related tests passed; final layout review in app underway.
SOURCE: The build and all regression tests passed. The app has not been deployed.
OUTPUT: Build and regression tests passed; app not deployed.
SOURCE: I recommend MIT, but the licence has not been selected yet. I will check GitHub sign-in next.
OUTPUT: MIT recommended; licence not selected. Planned: check GitHub sign-in.
SOURCE: The first command failed because the folder was missing. I created the folder and the retry succeeded.
OUTPUT: The first command failed because the folder was missing; the folder created succeeded.
SOURCE: The missing file may explain the failure, but I have not confirmed the cause.
OUTPUT: Missing file may explain failure; cause not confirmed.
```

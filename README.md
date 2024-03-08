# cleanup
* Toggles on the deletion of old production packages, unless no BRS backup exists.
* Removes all warning messages from emails, except when no BRS backup exists for production packages.
* All non-email warnings are appended to the job log file instead.
* Emails are only triggered by warnings that old production packages with no BRS backup is not deleted.
* Variable "WHITELIST" must be added to ecflow job task, jops_cleanup, or to any family above the task, for the job to run.


# OctopusDeploy-EnthusiasticPromotions
Contains the enthusiastic promoter script that pushes Octopus releases out the door.

This script is used as a runbook within the Octopus Server project which is run on a trigger to get the latest deployments for each environment in each channel and promotes them to the next environment if they have baked long enough in their current environment.

At Octopus, we're want green builds to mean that they're ready for release, which is part of why we have enthusiastic promotions now - developers can spend less time getting builds ready for customers and we can ship smaller, more often and to our own environments first so if things go wrong, we can catch them early and protect our customers. 

# Publishing

When pushing to main, this workflow will run: https://github.com/OctopusDeploy/OctopusDeploy-EnthusiasticPromotions/blob/main/.github/workflows/BuildTestPackagePush.yml. It runs the tests, packs the script, pushes it to octopus and re-publishes the runbook. Therefore, any pushes to the main branch will result in the runbook being updated automatically. 

# Contributing
Firstly, thanks for contributing! :tada:

1. Modify the tests to suit the change you want to make.
2. Modify the script to meet the new tests.
3. Run `Invoke-Pester` in the root directory to ensure all the tests pass
4. Create a pull request
5. Merge the pull request (GitHub Actions will run the tests for you and push your package to Deploy when successful)
6. Navigate to https://deploy.octopus.app and open the Octopus Server project in the Octopus Server space
7. Open the "[Enthusiastic Promotions](https://deploy.octopus.app/app#/Spaces-622/projects/octopus-server/operations/runbooks/Runbooks-661/overview)" runbook 
8. Click "publish" on the runbook and use the latest package 
9. Now Octopus will use the new enthusiastic promoter script!

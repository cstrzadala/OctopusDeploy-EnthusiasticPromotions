# OctopusDeploy-EnthusiasticPromotions
Contains the enthusiastic promoter script that pushes Octopus releases out the door.

This script is used as a runbook within the Octopus Server project which is run on a trigger to get the latest deployments for each environment in each channel and promotes them to the next environment if they have baked long enough in their current environment.

At Octopus, we're want green builds to mean that they're ready for release, which is part of why we have enthusiastic promotions now - developers can spend less time getting builds ready for customers and we can ship smaller, more often and to our own environments first so if things go wrong, we can catch them early and protect our customers. 

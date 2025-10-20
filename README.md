# Gooddeeds-chain Smart Contract

## Overview

**Gooddeeds-chain** is a Clarity smart contract for tracking NGO impact transparently on the Stacks blockchain.  
It enables registration and verification of NGOs, project creation, milestone management, donation tracking, and secure fund release based on verified milestones.

## Features

- **NGO Registration & Verification:** NGOs can register and be verified by the contract owner.
- **Project Management:** Registered NGOs can create projects with funding goals.
- **Milestone Tracking:** Projects can have milestones that require verification before funds are released.
- **Donation Handling:** Donors can contribute STX to projects; donations are tracked per donor and project.
- **Verifier Registry:** Owner can assign verifiers who are allowed to verify milestones.
- **Fund Release:** Funds are released to NGOs only after milestone verification.

## Events

Events are emitted for off-chain indexing:
- `ngo-registered`
- `ngo-verified`
- `project-created`
- `donation-received`
- `milestone-created`
- `milestone-verified`
- `funds-released`

## Usage

Deploy the contract using [Clarinet](https://docs.stacks.co/docs/clarinet/overview/) or compatible Stacks tools.

### Key Functions

- `register-ngo(name, metadata)` — Register a new NGO.
- `verify-ngo(ngo-id)` — Owner verifies an NGO.
- `create-project(ngo-id, title, description, goal)` — NGO creates a project.
- `donate(project-id, amount)` — Donor sends STX to a project.
- `create-milestone(project-id, title, description, amount)` — NGO adds a milestone.
- `verify-milestone(milestone-id)` — Verifier verifies a milestone.
- `release-funds(milestone-id)` — Owner or verifier releases funds for a verified milestone.

## Development

- Written in [Clarity](https://docs.stacks.co/docs/clarity/overview/).
- Compatible with Stacks 2.1+ and Clarinet.
- See contract comments for data structures and event shapes.

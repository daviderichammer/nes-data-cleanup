# NES Database Data Cleanup

This repository contains scripts and documentation for safely cleaning up old data from the NES database to reduce database size while maintaining data integrity.

## Overview

The cleanup process targets three main categories of data:
- Resident account information for accounts last billed more than 7 years ago
- Communities closed or "zy"ed more than 7 years ago (excluding those in legal hold)
- Readings not used for billing older than 2 years

## Safety First

This project prioritizes **zero false positives** - we will never delete data that should be retained. False negatives (missing some deletable data) are acceptable as the script runs periodically.

## Documentation

- [**Data Deletion Plan**](data-deletion-plan.md) - Comprehensive plan for implementing the cleanup process

## Repository Structure

```
├── README.md                 # This file
├── data-deletion-plan.md     # Detailed implementation plan
├── scripts/                  # Python scripts for data deletion
├── sql/                      # SQL queries and schema analysis
├── config/                   # Configuration files
└── docs/                     # Additional documentation
```

## Development Status

🚧 **In Development** - This project is currently in the planning and development phase.

## Getting Started

1. Review the [Data Deletion Plan](data-deletion-plan.md)
2. Ensure you have a complete database backup
3. Follow the implementation phases outlined in the plan

## Safety Features

- Mandatory dry-run mode by default
- Comprehensive logging and audit trails
- Transaction-based deletion with rollback capability
- Safety thresholds to prevent accidental mass deletions
- Optional archiving before deletion

## Contributing

This is a critical database maintenance project. All changes should be:
- Thoroughly tested on non-production data
- Reviewed for safety implications
- Documented with clear commit messages

## License

Internal project - not for public distribution.


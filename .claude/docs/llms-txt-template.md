# llms.txt Template

The `llms.txt` file is a standard "sitemap for AI" that helps AI agents navigate your project.

## Usage

Copy the template below to your project root as `llms.txt` and customize it:

```bash
cp .claude/docs/llms-txt-template.md ./llms.txt
# Then edit llms.txt to describe YOUR project
```

---

## Template

```txt
# Project Name

> One-line description of what this project does.

## Quick Start

Brief instructions for how to work with this project.

## Documentation Map

### Core Files
- /src/index.ts - Main entry point
- /src/config.ts - Configuration
- /package.json - Dependencies and scripts

### Key Directories
- /src/api/ - API endpoints
- /src/models/ - Data models
- /src/utils/ - Utility functions
- /tests/ - Test files

### Configuration
- /.env.example - Environment variables template
- /tsconfig.json - TypeScript configuration
- /docker-compose.yml - Docker setup

## Key Concepts

### Architecture
Describe your architecture here (e.g., "Express.js REST API with PostgreSQL").

### Patterns Used
- Pattern 1: Description
- Pattern 2: Description

### Important Conventions
- Convention 1
- Convention 2

## Commands

### Development
- `npm run dev` - Start development server
- `npm test` - Run tests
- `npm run lint` - Run linter

### Production
- `npm run build` - Build for production
- `npm start` - Start production server

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| DATABASE_URL | Database connection string | Yes |
| API_KEY | External API key | No |

## Sentinel Zones (Do Not Modify Without Approval)

- /src/auth/ - Authentication code
- /src/billing/ - Payment processing
- /migrations/ - Database migrations
```

---

## Tips

1. **Keep it updated** — Update `llms.txt` when you add major features or change architecture
2. **Be specific** — Include actual file paths, not generic placeholders
3. **Document conventions** — Help AI understand your coding style
4. **Mark sensitive areas** — Identify code that requires careful handling

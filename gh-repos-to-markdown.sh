#!/bin/bash

# Safe division function to prevent divide by zero errors
safe_division() {
  local numerator=$1
  local denominator=$2
  local default_value=${3:-"0.0"}
  
  if [ "$denominator" -eq 0 ]; then
    echo "$default_value"
  else
    # Calculate the division with scale=1
    local result=$(echo "scale=1; ($numerator / $denominator)" | bc)
    
    # If the result is "0" or "0.0", try with higher precision
    if [ "$result" = "0" ] || [ "$result" = "0.0" ] || [ "$result" = ".0" ]; then
      result=$(echo "scale=2; ($numerator / $denominator)" | bc)
      
      # If still zero, use a small non-zero value
      if [ "$result" = "0" ] || [ "$result" = "0.0" ] || [ "$result" = "0.00" ] || [ "$result" = ".0" ] || [ "$result" = ".00" ]; then
        if [ "$numerator" -ne 0 ]; then
          result="0.1" # Return a small non-zero value if numerator isn't zero
        else
          result="0"
        fi
      fi
    fi
    
    echo "$result"
  fi
}

# Set output filename
OUTPUT_FILE="github_repositories_complete.md"

# Repositories to ignore (space-separated list)
IGNORED_REPOS="zelhajou Projects"

# Set initial variables
PUBLIC_COUNT=0
TOTAL_STARS=0
TOTAL_FORKS=0
MOST_STARRED=""
MOST_STARRED_COUNT=0
MOST_FORKED=""
MOST_FORKED_COUNT=0

# Get GitHub username
USERNAME=$(gh api user --jq '.login')
FULL_NAME=$(gh api user --jq '.name')
BIO=$(gh api user --jq '.bio')
FOLLOWERS=$(gh api user --jq '.followers')
FOLLOWING=$(gh api user --jq '.following')
PROFILE_URL=$(gh api user --jq '.html_url')
PROFILE_IMG=$(gh api user --jq '.avatar_url')
USER_LOCATION=$(gh api user --jq '.location')
TWITTER=$(gh api user --jq '.twitter_username')
BLOG=$(gh api user --jq '.blog')

# Output status for GitHub Actions logs
echo "Generating markdown document of public repositories for user: $USERNAME (newest first)"
echo "Ignoring repositories: $IGNORED_REPOS"

# Create markdown header with user profile information and theme-aware styling
cat > "$OUTPUT_FILE" << EOF
# GitHub Profile: $FULL_NAME (@$USERNAME)

![Profile Views](https://komarev.com/ghpvc/?username=$USERNAME&color=blue)

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="$PROFILE_IMG">
    <source media="(prefers-color-scheme: light)" srcset="$PROFILE_IMG">
    <img src="$PROFILE_IMG" width="200" height="200" style="border-radius:50%">
  </picture>
  <h3>$FULL_NAME</h3>
  <p>$BIO</p>
  
  [![GitHub followers](https://img.shields.io/github/followers/$USERNAME?style=social)](${PROFILE_URL})
  [![Twitter: $TWITTER](https://img.shields.io/twitter/follow/$TWITTER?style=social)](https://twitter.com/$TWITTER)
</div>

## About Me
- 📍 Location: $USER_LOCATION
- 🔗 Website: [$BLOG]($BLOG)
- 👥 Followers: $FOLLOWERS | Following: $FOLLOWING

## Public Repositories (Newest First)

Last updated: $(date +"%B %d, %Y")

| Repository | Description | Created | Last Updated | Stars |
|------------|-------------|---------|-------------|-------|
EOF

# Process repositories
echo "Fetching repository data..."

# Get list of repos with createdAt field included
gh repo list --limit 1000 --json name,description,isPrivate,stargazerCount,forkCount,updatedAt,createdAt,diskUsage > /tmp/repo_data.json

# Count all repositories for total
gh repo list --limit 1000 --json name,isPrivate --jq '.[] | select(.isPrivate==false) | .name' > /tmp/public_repos.txt
PUBLIC_COUNT=$(wc -l < /tmp/public_repos.txt | tr -d ' ')
# Handle case where count is zero
PUBLIC_COUNT=${PUBLIC_COUNT:-0}

# Calculate all stars across all repos
if [ -f /tmp/public_repos.txt ]; then
  while read -r repo_name; do
    if [ -n "$repo_name" ]; then
      # Get stars for this repo
      stars=$(gh api repos/$USERNAME/$repo_name --jq '.stargazers_count')
      # Ensure stars is a number
      if [[ "$stars" =~ ^[0-9]+$ ]]; then
        TOTAL_STARS=$((TOTAL_STARS + stars))
      fi
    fi
  done < /tmp/public_repos.txt
fi

# Get total repo count
TOTAL_REPOS=$(gh repo list --limit 1000 | wc -l | tr -d ' ')
# Handle case where total count is zero
TOTAL_REPOS=${TOTAL_REPOS:-0}

# Calculate private repos, ensuring we don't get negative values
if [ "$TOTAL_REPOS" -ge "$PUBLIC_COUNT" ]; then
  PRIVATE_REPOS=$((TOTAL_REPOS - PUBLIC_COUNT))
else
  # If there's an inconsistency in counts, set private to zero
  PRIVATE_REPOS=0
fi

# Process JSON data, create a temporary file for sorting
jq -c '.[]' /tmp/repo_data.json | while read -r repo_entry; do
  # Extract repository name
  repo_name=$(echo "$repo_entry" | jq -r '.name')
  
  # Skip if no repo name is found
  if [ -z "$repo_name" ]; then
    continue
  fi
  
  # Skip ignored repositories
  if [[ " $IGNORED_REPOS " == *" $repo_name "* ]]; then
    continue
  fi
  
  # Extract other properties
  description=$(echo "$repo_entry" | jq -r '.description // "*No description*"')
  is_private=$(echo "$repo_entry" | jq -r '.isPrivate')
  stars=$(echo "$repo_entry" | jq -r '.stargazerCount')
  forks=$(echo "$repo_entry" | jq -r '.forkCount')
  updated=$(echo "$repo_entry" | jq -r '.updatedAt' | cut -dT -f1)
  created=$(echo "$repo_entry" | jq -r '.createdAt' | cut -dT -f1)
  
  # Skip private repositories
  if [ "$is_private" = "true" ]; then
    continue
  fi

  # Track statistics for public repositories
  # Convert stars and forks to numbers, default to 0 if empty or not a number
  if [[ "$stars" =~ ^[0-9]+$ ]]; then
    TOTAL_STARS=$((TOTAL_STARS + stars))
  fi
  
  if [[ "$forks" =~ ^[0-9]+$ ]]; then
    TOTAL_FORKS=$((TOTAL_FORKS + forks))
  fi
  
  # Track most starred and forked repos
  if [[ "$stars" =~ ^[0-9]+$ ]] && [ "$stars" -gt "$MOST_STARRED_COUNT" ]; then
    MOST_STARRED="$repo_name"
    MOST_STARRED_COUNT=$stars
  fi
  
  if [[ "$forks" =~ ^[0-9]+$ ]] && [ "$forks" -gt "$MOST_FORKED_COUNT" ]; then
    MOST_FORKED="$repo_name"
    MOST_FORKED_COUNT=$forks
  fi
  
  # Handle missing values
  description=${description:-"*No description*"}
  stars=${stars:-0}
  updated=${updated:-"Unknown"}
  created=${created:-"Unknown"}
  
  # Truncate long descriptions
  if [ ${#description} -gt 100 ]; then
    description="${description:0:97}..."
  fi
  
  # Escape any pipe characters in description
  description=$(echo "$description" | sed 's/|/\\|/g')
  
  # Get primary language for repository
  primary_lang=$(gh api repos/$USERNAME/$repo_name --jq '.language')
  
  # Add language information to the listing
  echo "$created|[$repo_name](https://github.com/$USERNAME/$repo_name)|$description|$created|$updated|$stars|$primary_lang" >> /tmp/repo_entries.txt
  
  # Get contributors count
  contributors_count=$(gh api repos/$USERNAME/$repo_name/contributors --jq 'length')
  # Make sure contributors_count is a number
  if [[ ! "$contributors_count" =~ ^[0-9]+$ ]]; then
    contributors_count=0
  fi
  echo "$repo_name:$contributors_count" >> /tmp/contributors.txt
  
  # Get languages for this repo and percentages
  gh api repos/$USERNAME/$repo_name/languages >> /tmp/repo_languages_$repo_name.json
done

# Save stats at once after all repos are processed
if [ -z "$MOST_STARRED" ]; then
  # If most starred repo is empty, find one
  if [ -f /tmp/repo_entries.txt ]; then
    # Get the repo with the highest stars
    HIGHEST_STARS_LINE=$(sort -t'|' -k6,6nr /tmp/repo_entries.txt | head -1)
    if [ -n "$HIGHEST_STARS_LINE" ]; then
      MOST_STARRED=$(echo "$HIGHEST_STARS_LINE" | cut -d'|' -f2 | sed -n 's/\[\(.*\)\].*/\1/p')
      MOST_STARRED_COUNT=$(echo "$HIGHEST_STARS_LINE" | cut -d'|' -f6)
    fi
  fi
fi

if [ -z "$MOST_FORKED" ]; then
  # If we have repos but no most forked, set to the first repo
  if [ -f /tmp/repo_entries.txt ]; then
    FIRST_REPO_LINE=$(head -1 /tmp/repo_entries.txt)
    if [ -n "$FIRST_REPO_LINE" ]; then
      MOST_FORKED=$(echo "$FIRST_REPO_LINE" | cut -d'|' -f2 | sed -n 's/\[\(.*\)\].*/\1/p')
      MOST_FORKED_COUNT=0
    fi
  fi
fi

# Make sure we have valid values for all stats
PUBLIC_COUNT=${PUBLIC_COUNT:-0}
TOTAL_STARS=${TOTAL_STARS:-0}
TOTAL_FORKS=${TOTAL_FORKS:-0}
MOST_STARRED=${MOST_STARRED:-"No repositories"}
MOST_STARRED_COUNT=${MOST_STARRED_COUNT:-0}
MOST_FORKED=${MOST_FORKED:-"No repositories"}
MOST_FORKED_COUNT=${MOST_FORKED_COUNT:-0}

echo "$PUBLIC_COUNT $TOTAL_STARS $TOTAL_FORKS $MOST_STARRED $MOST_STARRED_COUNT $MOST_FORKED $MOST_FORKED_COUNT" > /tmp/repo_stats.txt

# Sort by creation date in reverse order (newest first) and append to markdown
if [ -f /tmp/repo_entries.txt ]; then
  sort -r /tmp/repo_entries.txt | while IFS="|" read -r sort_date repo_link desc created updated stars lang; do
    # Add language badge if available
    if [ "$lang" != "null" ] && [ -n "$lang" ]; then
      # Match language to appropriate color
      case "$lang" in
        "JavaScript") color="yellow" ;;
        "Python") color="blue" ;;
        "Java") color="orange" ;;
        "HTML") color="red" ;;
        "CSS") color="purple" ;;
        "TypeScript") color="blue" ;;
        "C++") color="green" ;;
        "PHP") color="pink" ;;
        *) color="gray" ;;
      esac
      
      lang_badge="![](https://img.shields.io/badge/-$lang-$color)"
      desc="$desc $lang_badge"
    fi
    
    echo "| $repo_link | $desc | $created | $updated | $stars |" >> "$OUTPUT_FILE"
  done
fi

# Create summary card at the top
echo "" >> "$OUTPUT_FILE"
echo "## Repository Statistics" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Read the calculated statistics
if [ -f /tmp/repo_stats.txt ]; then
  read PUBLIC_COUNT TOTAL_STARS TOTAL_FORKS MOST_STARRED MOST_STARRED_COUNT MOST_FORKED MOST_FORKED_COUNT < /tmp/repo_stats.txt
fi

# Create summary cards with emojis - with adaptive theming
cat >> "$OUTPUT_FILE" << EOF
<div align="center">
  <table>
    <tr>
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Total%20Repositories-$TOTAL_REPOS-blue?style=for-the-badge&color=3498db">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Total%20Repositories-$TOTAL_REPOS-blue?style=for-the-badge&color=3498db">
          <img alt="Total Repositories" src="https://img.shields.io/badge/Total%20Repositories-$TOTAL_REPOS-blue?style=for-the-badge&color=3498db">
        </picture>
      </td>
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Public%20Repositories-$PUBLIC_COUNT-green?style=for-the-badge&color=2ecc71">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Public%20Repositories-$PUBLIC_COUNT-green?style=for-the-badge&color=2ecc71">
          <img alt="Public Repositories" src="https://img.shields.io/badge/Public%20Repositories-$PUBLIC_COUNT-green?style=for-the-badge&color=2ecc71">
        </picture>
      </td>
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Private%20Repositories-$PRIVATE_REPOS-red?style=for-the-badge&color=e74c3c">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Private%20Repositories-$PRIVATE_REPOS-red?style=for-the-badge&color=e74c3c">
          <img alt="Private Repositories" src="https://img.shields.io/badge/Private%20Repositories-$PRIVATE_REPOS-red?style=for-the-badge&color=e74c3c">
        </picture>
      </td>
    </tr>
    <tr>
      <td align="center" colspan="3">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
          <img alt="Total Stars" src="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
        </picture>
      </td>
    </tr>
  </table>
</div>

### Notable Repositories
- 🌟 **Most starred:** [$MOST_STARRED](https://github.com/$USERNAME/$MOST_STARRED) with $MOST_STARRED_COUNT stars
EOF

# Add repository age statistics
if [ -f /tmp/repo_entries.txt ] && [ -s /tmp/repo_entries.txt ]; then
  OLDEST_REPO_INFO=$(sort /tmp/repo_entries.txt | head -1)
  NEWEST_REPO_INFO=$(sort -r /tmp/repo_entries.txt | head -1)
  
  OLDEST_REPO_DATE=$(echo "$OLDEST_REPO_INFO" | cut -d'|' -f4)
  OLDEST_REPO_NAME=$(echo "$OLDEST_REPO_INFO" | cut -d'|' -f2 | sed -n 's/\[\(.*\)\].*/\1/p')
  
  NEWEST_REPO_DATE=$(echo "$NEWEST_REPO_INFO" | cut -d'|' -f4)
  NEWEST_REPO_NAME=$(echo "$NEWEST_REPO_INFO" | cut -d'|' -f2 | sed -n 's/\[\(.*\)\].*/\1/p')
  
  echo -e "\n### Repository Timeline" >> "$OUTPUT_FILE"
  echo "- 📅 **First repository:** [$OLDEST_REPO_NAME](https://github.com/$USERNAME/$OLDEST_REPO_NAME) created on $OLDEST_REPO_DATE" >> "$OUTPUT_FILE"
  echo "- 🆕 **Most recent repository:** [$NEWEST_REPO_NAME](https://github.com/$USERNAME/$NEWEST_REPO_NAME) created on $NEWEST_REPO_DATE" >> "$OUTPUT_FILE"
  
  # Calculate GitHub account age
  ACCOUNT_INFO=$(gh api user --jq '.created_at')
  ACCOUNT_CREATED=$(echo "$ACCOUNT_INFO" | cut -dT -f1)
  CURRENT_DATE=$(date +"%Y-%m-%d")
  
  # Calculate account age in years (approximate)
  ACCOUNT_YEAR=$(echo "$ACCOUNT_CREATED" | cut -d'-' -f1)
  CURRENT_YEAR=$(echo "$CURRENT_DATE" | cut -d'-' -f1)
  ACCOUNT_AGE=$((CURRENT_YEAR - ACCOUNT_YEAR))
  
  echo "- 🎂 **GitHub account age:** Approximately $ACCOUNT_AGE years (created on $ACCOUNT_CREATED)" >> "$OUTPUT_FILE"
  
  # Calculate average repositories per year
  if [ "$ACCOUNT_AGE" -eq 0 ] || [ -z "$ACCOUNT_AGE" ]; then
    REPOS_PER_YEAR="$PUBLIC_COUNT (account created this year)"
  else
    REPOS_PER_YEAR=$(safe_division "$PUBLIC_COUNT" "$ACCOUNT_AGE")
    
    # Make sure we don't display "0" for the repos per year
    if [ "$REPOS_PER_YEAR" = "0.0" ] || [ "$REPOS_PER_YEAR" = "0" ] || [ "$REPOS_PER_YEAR" = ".0" ]; then
      REPOS_PER_YEAR=$(bc <<< "scale=1; $PUBLIC_COUNT / $ACCOUNT_AGE")
      # If still zero, use a more user-friendly format
      if [ "$REPOS_PER_YEAR" = "0" ] || [ "$REPOS_PER_YEAR" = ".0" ] || [ "$REPOS_PER_YEAR" = "0.0" ]; then
        # Create a more natural-sounding message
        if [ "$PUBLIC_COUNT" -eq 1 ]; then
          REPOS_PER_YEAR="$PUBLIC_COUNT repository in $ACCOUNT_AGE years"
        else
          REPOS_PER_YEAR="$PUBLIC_COUNT repositories in $ACCOUNT_AGE years"
        fi
      fi
    fi
  fi
  echo "- 📊 **Average creation rate:** $REPOS_PER_YEAR" >> "$OUTPUT_FILE"
fi

# Generate contribution activity heatmap link with theme variants
echo -e "\n### Contribution Activity" >> "$OUTPUT_FILE"
echo -e "\n<div align=\"center\">" >> "$OUTPUT_FILE"
echo -e "  <picture>" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: dark)\" srcset=\"https://github-readme-streak-stats.herokuapp.com/?user=$USERNAME&theme=dark\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: light)\" srcset=\"https://github-readme-streak-stats.herokuapp.com/?user=$USERNAME&theme=default\">" >> "$OUTPUT_FILE"
echo -e "    <img src=\"https://github-readme-streak-stats.herokuapp.com/?user=$USERNAME\" width=\"500\">" >> "$OUTPUT_FILE"
echo -e "  </picture>" >> "$OUTPUT_FILE"
echo -e "</div>" >> "$OUTPUT_FILE"

# Generate language statistics using GitHub's API with theme awareness
echo -e "\n## Language Statistics" >> "$OUTPUT_FILE"

# Create a GitHub-style language bar with theme variants
echo -e "\n### Language Distribution" >> "$OUTPUT_FILE"
echo -e "\nLanguage composition across all repositories:" >> "$OUTPUT_FILE"
echo -e "\n<div align=\"left\">" >> "$OUTPUT_FILE"
echo -e "  <picture>" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: dark)\" srcset=\"https://github-readme-stats.vercel.app/api/top-langs/?username=$USERNAME&layout=compact&hide_border=true&langs_count=10&theme=dark\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: light)\" srcset=\"https://github-readme-stats.vercel.app/api/top-langs/?username=$USERNAME&layout=compact&hide_border=true&langs_count=10&theme=default\">" >> "$OUTPUT_FILE"
echo -e "    <img src=\"https://github-readme-stats.vercel.app/api/top-langs/?username=$USERNAME&layout=compact&hide_border=true&langs_count=10\" width=\"400\">" >> "$OUTPUT_FILE"
echo -e "  </picture>" >> "$OUTPUT_FILE"
echo -e "</div>\n" >> "$OUTPUT_FILE"

# Add a more detailed language breakdown
echo -e "\n### Detailed Language Breakdown" >> "$OUTPUT_FILE"

# Create temp file for all languages
> /tmp/all_languages.txt
for repo in $(gh repo list --json name,isPrivate --jq '.[] | select(.isPrivate==false) | .name' | grep -v "$IGNORED_REPOS"); do
  # Get languages for this repo
  gh api repos/$USERNAME/$repo/languages --jq 'keys[]' 2>/dev/null >> /tmp/all_languages.txt
done

if [ -f /tmp/all_languages.txt ]; then
  # Count total repos
  TOTAL_REPOS=$PUBLIC_COUNT
  
  # Create a markdown table for language statistics
  echo -e "\n| Language | Repository Count |" >> "$OUTPUT_FILE"
  echo -e "|----------|------------------|" >> "$OUTPUT_FILE"
  
  # Check if we have any languages before processing
  if [ -s /tmp/all_languages.txt ]; then
    # Generate statistics
    cat /tmp/all_languages.txt | sort | uniq -c | sort -nr | head -15 | while read -r count language; do
      if [ -n "$language" ]; then
        # Remove quotes if present
        language=$(echo "$language" | tr -d '"')
        
        # Add row to table
        echo "| **$language** | $count |" >> "$OUTPUT_FILE"
      fi
    done
  else
    # No languages detected, add a placeholder row
    echo "| **No language data available** | - |" >> "$OUTPUT_FILE"
  fi
fi

# Add language usage trends with theme awareness
echo -e "\n### Language Distribution Visualization" >> "$OUTPUT_FILE"
echo -e "\n<div align=\"center\" style=\"display: flex; flex-wrap: wrap; justify-content: center; gap: 10px;\">" >> "$OUTPUT_FILE"
echo -e "  <picture style=\"max-width: 49%;\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: dark)\" srcset=\"https://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=$USERNAME&theme=github_dark\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: light)\" srcset=\"https://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=$USERNAME&theme=github\">" >> "$OUTPUT_FILE"
echo -e "    <img src=\"https://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=$USERNAME&theme=github\" width=\"400\">" >> "$OUTPUT_FILE"
echo -e "  </picture>" >> "$OUTPUT_FILE"
echo -e "  <picture style=\"max-width: 49%;\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: dark)\" srcset=\"https://github-profile-summary-cards.vercel.app/api/cards/most-commit-language?username=$USERNAME&theme=github_dark\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: light)\" srcset=\"https://github-profile-summary-cards.vercel.app/api/cards/most-commit-language?username=$USERNAME&theme=github\">" >> "$OUTPUT_FILE"
echo -e "    <img src=\"https://github-profile-summary-cards.vercel.app/api/cards/most-commit-language?username=$USERNAME&theme=github\" width=\"400\">" >> "$OUTPUT_FILE"
echo -e "  </picture>" >> "$OUTPUT_FILE"
echo -e "</div>" >> "$OUTPUT_FILE"

# Add contributor statistics if available
if [ -f /tmp/contributors.txt ]; then
  TOTAL_CONTRIBUTORS=$(cat /tmp/contributors.txt | awk -F':' '{sum+=$2} END {print sum}')
  # Set default value if no contributors found
  TOTAL_CONTRIBUTORS=${TOTAL_CONTRIBUTORS:-0}
  
  MAX_CONTRIBUTORS=0
  MAX_CONTRIB_REPO=""
  
  # Check if contributors file has any content
  if [ -s /tmp/contributors.txt ]; then
    while IFS=':' read -r repo contrib; do
      # Ensure contributor count is a number
      if [[ "$contrib" =~ ^[0-9]+$ ]] && [ "$contrib" -gt "$MAX_CONTRIBUTORS" ]; then
        MAX_CONTRIBUTORS=$contrib
        MAX_CONTRIB_REPO=$repo
      fi
    done < /tmp/contributors.txt
  fi
  
  # Default to the first repo if no collaborative project was found
  if [ -z "$MAX_CONTRIB_REPO" ] && [ -s /tmp/repo_entries.txt ]; then
    FIRST_REPO_LINE=$(head -1 /tmp/repo_entries.txt)
    MAX_CONTRIB_REPO=$(echo "$FIRST_REPO_LINE" | cut -d'|' -f2 | sed -n 's/\[\(.*\)\].*/\1/p')
    MAX_CONTRIBUTORS=1
  fi
  
  echo -e "\n## Collaboration Stats" >> "$OUTPUT_FILE"
  echo -e "- 👥 **Total contributors across all repositories:** $TOTAL_CONTRIBUTORS" >> "$OUTPUT_FILE"
  
  if [ -n "$MAX_CONTRIB_REPO" ]; then
    echo -e "- 🤝 **Most collaborative project:** [$MAX_CONTRIB_REPO](https://github.com/$USERNAME/$MAX_CONTRIB_REPO) with $MAX_CONTRIBUTORS contributors" >> "$OUTPUT_FILE"
  else
    echo -e "- 🤝 **No collaborative projects detected**" >> "$OUTPUT_FILE"
  fi
fi

# Add commit frequency data with theme awareness
echo -e "\n## Commit Activity" >> "$OUTPUT_FILE"
echo -e "\n<div align=\"center\">" >> "$OUTPUT_FILE"
echo -e "  <picture>" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: dark)\" srcset=\"https://github-readme-activity-graph.vercel.app/graph?username=$USERNAME&theme=github-dark\">" >> "$OUTPUT_FILE"
echo -e "    <source media=\"(prefers-color-scheme: light)\" srcset=\"https://github-readme-activity-graph.vercel.app/graph?username=$USERNAME&theme=github-light\">" >> "$OUTPUT_FILE"
echo -e "    <img src=\"https://github-readme-activity-graph.vercel.app/graph?username=$USERNAME&theme=github-light\" width=\"100%\">" >> "$OUTPUT_FILE"
echo -e "  </picture>" >> "$OUTPUT_FILE"
echo -e "</div>" >> "$OUTPUT_FILE"

# Add footer with social links
echo -e "\n---\n" >> "$OUTPUT_FILE"
echo -e "<div align=\"center\">" >> "$OUTPUT_FILE"
echo -e "\n### Connect With Me\n" >> "$OUTPUT_FILE"

if [ "$TWITTER" != "null" ] && [ -n "$TWITTER" ]; then
  echo -e "[![Twitter](https://img.shields.io/badge/X-%23121011.svg?logo=x&logoColor=white)](https://x.com/$TWITTER) " >> "$OUTPUT_FILE"
fi

echo -e "[![GitHub](https://img.shields.io/badge/GitHub-%23121011.svg?logo=github&logoColor=white)](https://github.com/$USERNAME) " >> "$OUTPUT_FILE"

if [ "$BLOG" != "null" ] && [ -n "$BLOG" ]; then
  echo -e "[![Website](https://img.shields.io/badge/Website-%23000000.svg?logo=firefox&logoColor=white)]($BLOG) " >> "$OUTPUT_FILE"
fi

echo -e "</div>\n" >> "$OUTPUT_FILE"

echo -e "\n<div align=\"center\"><small>Last updated: $(date '+%B %d, %Y')</small></div>" >> "$OUTPUT_FILE"

# Clean up temporary files
rm -f /tmp/repo_data.json /tmp/repo_entries.txt /tmp/repo_stats.txt /tmp/all_languages.txt /tmp/contributors.txt /tmp/language_totals.txt /tmp/language_sorted.txt
rm -f /tmp/repo_languages_*

echo "README generation complete! Output saved to $OUTPUT_FILE"

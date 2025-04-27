#!/bin/bash

# ssh-keygen -t ed25519 -f ./github_actions_key -N ""


# Safe division function to prevent divide by zero errors
safe_division() {
  local numerator=$1
  local denominator=$2
  local default_value=${3:-"0.0"}
  
  if [ "$denominator" -eq 0 ]; then
    echo "$default_value"
  else
    echo "scale=1; ($numerator / $denominator)" | bc
  fi
}

# Safe bar generation function
generate_bar() {
  local percentage=$1
  local max_length=${2:-20}
  
  if [ "$percentage" = "0.0" ] || [ -z "$percentage" ]; then
    echo ""
  else
    local bar_length=$(echo "scale=0; ($percentage * $max_length) / 100" | bc)
    printf '%*s' "$bar_length" | tr ' ' '█'
  fi
}

# Set output filename
OUTPUT_FILE="github_repositories_complete.md"

# Repositories to ignore (space-separated list)
IGNORED_REPOS="zelhajou Projects"

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

| Repository | Description | Created | Last Updated | Stars | Forks | Size |
|------------|-------------|---------|-------------|-------|-------|------|
EOF

# Process repositories
echo "Fetching repository data..."

# Get list of repos with createdAt field included
gh repo list --limit 1000 --json name,description,isPrivate,stargazerCount,forkCount,updatedAt,createdAt,diskUsage > /tmp/repo_data.json

# Save statistics data for later use
PUBLIC_COUNT=0
TOTAL_STARS=0
TOTAL_FORKS=0
TOTAL_SIZE=0
MOST_STARRED=""
MOST_STARRED_COUNT=0
MOST_FORKED=""
MOST_FORKED_COUNT=0

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
  size=$(echo "$repo_entry" | jq -r '.diskUsage')
  
  # Skip private repositories
  if [ "$is_private" = "true" ]; then
    continue
  fi

  # Track statistics for public repositories
  PUBLIC_COUNT=$((PUBLIC_COUNT + 1))
  TOTAL_STARS=$((TOTAL_STARS + stars))
  TOTAL_FORKS=$((TOTAL_FORKS + forks))
  TOTAL_SIZE=$((TOTAL_SIZE + size))
  
  # Track most starred and forked repos
  if [ "$stars" -gt "$MOST_STARRED_COUNT" ]; then
    MOST_STARRED="$repo_name"
    MOST_STARRED_COUNT=$stars
  fi
  
  if [ "$forks" -gt "$MOST_FORKED_COUNT" ]; then
    MOST_FORKED="$repo_name"
    MOST_FORKED_COUNT=$forks
  fi
  
  # Handle missing values
  description=${description:-"*No description*"}
  stars=${stars:-0}
  forks=${forks:-0}
  updated=${updated:-"Unknown"}
  created=${created:-"Unknown"}
  size=${size:-0}
  
  # Convert size from KB to MB if larger than 1000
  if [ "$size" -gt 1000 ]; then
    size_display="$(echo "scale=1; $size/1024" | bc) MB"
  else
    size_display="${size} KB"
  fi
  
  # Truncate long descriptions
  if [ ${#description} -gt 100 ]; then
    description="${description:0:97}..."
  fi
  
  # Escape any pipe characters in description
  description=$(echo "$description" | sed 's/|/\\|/g')
  
  # Get primary language for repository
  primary_lang=$(gh api repos/$USERNAME/$repo_name --jq '.language')
  
  # Add language and size information to the listing
  echo "$created|[$repo_name](https://github.com/$USERNAME/$repo_name)|$description|$created|$updated|$stars|$forks|$size_display|$primary_lang" >> /tmp/repo_entries.txt
  
  # Get contributors count
  contributors_count=$(gh api repos/$USERNAME/$repo_name/contributors --jq 'length')
  echo "$repo_name:$contributors_count" >> /tmp/contributors.txt
  
  # Get languages for this repo and percentages
  gh api repos/$USERNAME/$repo_name/languages >> /tmp/repo_languages_$repo_name.json
done

# Save stats at once after all repos are processed
echo "$PUBLIC_COUNT $TOTAL_STARS $TOTAL_FORKS $TOTAL_SIZE $MOST_STARRED $MOST_STARRED_COUNT $MOST_FORKED $MOST_FORKED_COUNT" > /tmp/repo_stats.txt

# Sort by creation date in reverse order (newest first) and append to markdown
if [ -f /tmp/repo_entries.txt ]; then
  sort -r /tmp/repo_entries.txt | while IFS="|" read -r sort_date repo_link desc created updated stars forks size lang; do
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
    
    echo "| $repo_link | $desc | $created | $updated | $stars | $forks | $size |" >> "$OUTPUT_FILE"
  done
fi

# Create summary card at the top
echo "" >> "$OUTPUT_FILE"
echo "## Repository Statistics" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Read the calculated statistics
if [ -f /tmp/repo_stats.txt ]; then
  read PUBLIC_COUNT TOTAL_STARS TOTAL_FORKS TOTAL_SIZE MOST_STARRED MOST_STARRED_COUNT MOST_FORKED MOST_FORKED_COUNT < /tmp/repo_stats.txt
fi

# Count all repositories for total
TOTAL_REPOS=$(gh repo list --limit 1000 | wc -l | tr -d ' ')
PRIVATE_REPOS=$((TOTAL_REPOS - PUBLIC_COUNT))

# Calculate total size in human-readable format
if [ "$TOTAL_SIZE" -gt 1000000 ]; then
  TOTAL_SIZE_DISPLAY="$(echo "scale=2; $TOTAL_SIZE/1048576" | bc) GB"
elif [ "$TOTAL_SIZE" -gt 1000 ]; then
  TOTAL_SIZE_DISPLAY="$(echo "scale=2; $TOTAL_SIZE/1024" | bc) MB"
else
  TOTAL_SIZE_DISPLAY="$TOTAL_SIZE KB"
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
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
          <img alt="Total Stars" src="https://img.shields.io/badge/Total%20Stars-$TOTAL_STARS-yellow?style=for-the-badge&color=f1c40f">
        </picture>
      </td>
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Total%20Forks-$TOTAL_FORKS-orange?style=for-the-badge&color=e67e22">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Total%20Forks-$TOTAL_FORKS-orange?style=for-the-badge&color=e67e22">
          <img alt="Total Forks" src="https://img.shields.io/badge/Total%20Forks-$TOTAL_FORKS-orange?style=for-the-badge&color=e67e22">
        </picture>
      </td>
      <td align="center">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Total%20Size-$TOTAL_SIZE_DISPLAY-lightgrey?style=for-the-badge&color=95a5a6">
          <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Total%20Size-$TOTAL_SIZE_DISPLAY-lightgrey?style=for-the-badge&color=95a5a6">
          <img alt="Total Size" src="https://img.shields.io/badge/Total%20Size-$TOTAL_SIZE_DISPLAY-lightgrey?style=for-the-badge&color=95a5a6">
        </picture>
      </td>
    </tr>
  </table>
</div>

### Notable Repositories
- 🌟 **Most starred:** [$MOST_STARRED](https://github.com/$USERNAME/$MOST_STARRED) with $MOST_STARRED_COUNT stars
- 🍴 **Most forked:** [$MOST_FORKED](https://github.com/$USERNAME/$MOST_FORKED) with $MOST_FORKED_COUNT forks
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
  fi
  echo "- 📊 **Average creation rate:** $REPOS_PER_YEAR repositories per year" >> "$OUTPUT_FILE"
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
  echo -e "\n| Language | Repository Count | Percentage | Bar |" >> "$OUTPUT_FILE"
  echo -e "|----------|------------------|------------|-----|" >> "$OUTPUT_FILE"
  
  # Generate statistics with visual bars
  cat /tmp/all_languages.txt | sort | uniq -c | sort -nr | head -15 | while read -r count language; do
    if [ -n "$language" ]; then
      # Remove quotes if present
      language=$(echo "$language" | tr -d '"')
      
      # Calculate percentage of repos using this language
      if [ "$TOTAL_REPOS" -eq 0 ] || [ -z "$TOTAL_REPOS" ]; then
        PERCENTAGE="0.0"
        BAR=""
      else
        PERCENTAGE=$(safe_division "($count * 100)" "$TOTAL_REPOS")
        BAR=$(generate_bar "$PERCENTAGE")
      fi
      
      # Add row to table with visual bar
      echo "| **$language** | $count | $PERCENTAGE% | $BAR |" >> "$OUTPUT_FILE"
    fi
  done
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
  MAX_CONTRIBUTORS=0
  MAX_CONTRIB_REPO=""
  
  while IFS=':' read -r repo contrib; do
    if [ "$contrib" -gt "$MAX_CONTRIBUTORS" ]; then
      MAX_CONTRIBUTORS=$contrib
      MAX_CONTRIB_REPO=$repo
    fi
  done < /tmp/contributors.txt
  
  echo -e "\n## Collaboration Stats" >> "$OUTPUT_FILE"
  echo -e "- 👥 **Total contributors across all repositories:** $TOTAL_CONTRIBUTORS" >> "$OUTPUT_FILE"
  echo -e "- 🤝 **Most collaborative project:** [$MAX_CONTRIB_REPO](https://github.com/$USERNAME/$MAX_CONTRIB_REPO) with $MAX_CONTRIBUTORS contributors" >> "$OUTPUT_FILE"
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
rm -f /tmp/repo_data.json /tmp/repo_entries.txt /tmp/repo_stats.txt /tmp/all_languages.txt /tmp/contributors.txt /tmp/all_languages_with_bytes.txt /tmp/language_totals.txt /tmp/language_sorted.txt
rm -f /tmp/repo_languages_*

echo "README generation complete! Output saved to $OUTPUT_FILE"

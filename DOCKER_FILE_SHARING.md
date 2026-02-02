# Docker File Sharing Configuration

To enable automatic database initialization, you need to configure Docker Desktop to share the project directory.

## Steps:

1. **Open Docker Desktop**
   - Click the Docker icon (whale) in your menu bar (top right)
   - Select **"Settings"** or **"Preferences"** (depending on your version)

2. **Navigate to File Sharing**
   - Look for **"Resources"** in the left sidebar
   - Click on **"Resources"** or **"Advanced"**
   - Then click on **"File Sharing"** tab

3. **Add the directory**
   - You should see a list of shared directories
   - Click the **"+"** button (usually at the bottom or top of the list)
   - Type or browse to: `/Users/sbecker11/workspace-ecommerce-semantic-search`
   - Press Enter or click outside the field

4. **Save the changes**
   - Look for one of these buttons (location varies by version):
     - **"Apply & Restart"** (bottom right or bottom center)
     - **"Apply"** button (may require clicking, then Docker restarts automatically)
     - **"Save"** button
     - Changes may auto-save in some versions
   - Docker Desktop will restart automatically when you save

5. **Alternative: If you can't find the button**
   - Try clicking anywhere outside the file sharing list
   - Or close the Settings window - changes may auto-save
   - Or look for a **"Restart"** option in the Docker Desktop menu

6. **Verify the directory is added**
   - The directory should appear in the File Sharing list
   - Wait for Docker to finish restarting (whale icon stops animating)

7. **Test the setup**
   ```bash
   cd /Users/sbecker11/workspace-ecommerce-semantic-search/ecommerce-semantic-search
   docker-compose down
   docker-compose up -d postgres
   ```

## If you still can't find it:

**Option A: Check Docker Desktop version**
- Some newer versions auto-save changes
- Try just adding the directory and closing Settings

**Option B: Use manual initialization instead**
- You don't need file sharing if you use manual initialization
- See the "Alternative" section below

## Alternative: Use Manual Initialization

If you prefer not to configure file sharing, you can initialize the database manually:

```bash
# Start postgres without the file mount
# (remove the init-db.sql volume line from docker-compose.yml)

# Then initialize manually:
docker-compose exec -T postgres psql -U postgres -d ecommerce < infrastructure/init-db.sql
```

Or use the helper script:
```bash
./infrastructure/init-database.sh
```

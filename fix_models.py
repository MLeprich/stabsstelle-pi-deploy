#!/usr/bin/env python3
import os
import glob

# Fix all model files to use String instead of UUID
models_path = "/app/app/models"
for model_file in glob.glob(f"{models_path}/*.py"):
    with open(model_file, 'r') as f:
        content = f.read()
    
    # Replace UUID imports
    content = content.replace("from sqlalchemy.dialects.postgresql import UUID", 
                              "from app.utils.uuid_compat import UUID")
    
    # Remove as_uuid parameter
    content = content.replace("UUID(as_uuid=True)", "UUID()")
    
    with open(model_file, 'w') as f:
        f.write(content)

print("Models fixed for SQLite UUID compatibility")

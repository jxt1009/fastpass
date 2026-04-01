#!/bin/bash

# FastTrack Database Backup and Restore Script
# Usage:
#   ./backup-restore.sh backup          - Create a manual backup
#   ./backup-restore.sh restore <file>  - Restore from a backup file
#   ./backup-restore.sh list            - List all backups
#   ./backup-restore.sh clean           - Clean old backups (>30 days)

set -e

NAMESPACE="default"
POSTGRES_POD=$(kubectl get pod -n $NAMESPACE -l app=fasttrack-postgres -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="/backups"

if [ -z "$POSTGRES_POD" ]; then
    echo "❌ Error: PostgreSQL pod not found"
    echo "   Make sure fasttrack-postgres is deployed"
    exit 1
fi

case "$1" in
    backup)
        echo "📦 Creating manual backup..."
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="fasttrack_backup_${TIMESTAMP}.sql"
        
        kubectl exec -n $NAMESPACE $POSTGRES_POD -- sh -c "
            pg_dump -U fasttrack -d fasttrack > ${BACKUP_DIR}/${BACKUP_FILE}
            gzip ${BACKUP_DIR}/${BACKUP_FILE}
            ls -lh ${BACKUP_DIR}/${BACKUP_FILE}.gz
        "
        
        echo "✅ Backup created: ${BACKUP_FILE}.gz"
        echo ""
        echo "To download to local machine:"
        echo "kubectl cp -n $NAMESPACE $POSTGRES_POD:${BACKUP_DIR}/${BACKUP_FILE}.gz ./${BACKUP_FILE}.gz"
        ;;
        
    restore)
        if [ -z "$2" ]; then
            echo "❌ Error: Backup file not specified"
            echo "Usage: $0 restore <backup-file>"
            echo ""
            echo "Available backups:"
            kubectl exec -n $NAMESPACE $POSTGRES_POD -- ls -lh $BACKUP_DIR/
            exit 1
        fi
        
        BACKUP_FILE="$2"
        
        echo "⚠️  WARNING: This will restore the database from backup"
        echo "   Current data will be OVERWRITTEN"
        echo "   Backup file: $BACKUP_FILE"
        echo ""
        read -p "Are you sure? (type 'yes' to continue): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "❌ Restore cancelled"
            exit 1
        fi
        
        echo "📥 Restoring from backup..."
        
        # Check if file is gzipped
        if [[ $BACKUP_FILE == *.gz ]]; then
            kubectl exec -n $NAMESPACE $POSTGRES_POD -- sh -c "
                gunzip -c ${BACKUP_DIR}/${BACKUP_FILE} | psql -U fasttrack -d fasttrack
            "
        else
            kubectl exec -n $NAMESPACE $POSTGRES_POD -- sh -c "
                psql -U fasttrack -d fasttrack < ${BACKUP_DIR}/${BACKUP_FILE}
            "
        fi
        
        echo "✅ Database restored successfully"
        ;;
        
    list)
        echo "📋 Available backups:"
        kubectl exec -n $NAMESPACE $POSTGRES_POD -- sh -c "
            ls -lh ${BACKUP_DIR}/ | grep fasttrack_backup || echo 'No backups found'
        "
        ;;
        
    clean)
        echo "🧹 Cleaning old backups (>30 days)..."
        kubectl exec -n $NAMESPACE $POSTGRES_POD -- sh -c "
            find ${BACKUP_DIR} -name 'fasttrack_backup_*.sql.gz' -mtime +30 -ls -delete
        "
        echo "✅ Cleanup complete"
        ;;
        
    download)
        if [ -z "$2" ]; then
            echo "❌ Error: Backup file not specified"
            echo "Usage: $0 download <backup-file>"
            exit 1
        fi
        
        BACKUP_FILE="$2"
        LOCAL_FILE="./$(basename $BACKUP_FILE)"
        
        echo "⬇️  Downloading backup..."
        kubectl cp -n $NAMESPACE $POSTGRES_POD:${BACKUP_DIR}/${BACKUP_FILE} ${LOCAL_FILE}
        echo "✅ Downloaded to: ${LOCAL_FILE}"
        ;;
        
    upload)
        if [ -z "$2" ]; then
            echo "❌ Error: Local backup file not specified"
            echo "Usage: $0 upload <local-file>"
            exit 1
        fi
        
        LOCAL_FILE="$2"
        REMOTE_FILE="${BACKUP_DIR}/$(basename $LOCAL_FILE)"
        
        if [ ! -f "$LOCAL_FILE" ]; then
            echo "❌ Error: File not found: $LOCAL_FILE"
            exit 1
        fi
        
        echo "⬆️  Uploading backup..."
        kubectl cp -n $NAMESPACE ${LOCAL_FILE} $POSTGRES_POD:${REMOTE_FILE}
        echo "✅ Uploaded to: ${REMOTE_FILE}"
        echo ""
        echo "To restore, run:"
        echo "$0 restore $(basename $LOCAL_FILE)"
        ;;
        
    test)
        echo "🧪 Testing database connection..."
        kubectl exec -n $NAMESPACE $POSTGRES_POD -- psql -U fasttrack -d fasttrack -c "SELECT 'Connection successful!' as status;"
        echo ""
        echo "📊 Database size:"
        kubectl exec -n $NAMESPACE $POSTGRES_POD -- psql -U fasttrack -d fasttrack -c "
            SELECT 
                pg_size_pretty(pg_database_size('fasttrack')) as size,
                (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') as table_count;
        "
        ;;
        
    *)
        echo "FastTrack Database Backup & Restore"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  backup              Create a manual backup"
        echo "  restore <file>      Restore from backup file"
        echo "  list                List all available backups"
        echo "  clean               Remove backups older than 30 days"
        echo "  download <file>     Download backup to local machine"
        echo "  upload <file>       Upload local backup to server"
        echo "  test                Test database connection"
        echo ""
        echo "Examples:"
        echo "  $0 backup"
        echo "  $0 list"
        echo "  $0 restore fasttrack_backup_20260401_020000.sql.gz"
        echo "  $0 download fasttrack_backup_20260401_020000.sql.gz"
        echo ""
        echo "Automated backups run daily at 2 AM (configured in backup-cronjob.yaml)"
        exit 1
        ;;
esac

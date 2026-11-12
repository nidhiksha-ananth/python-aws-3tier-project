from sqlalchemy.exc import SQLAlchemyError

from flask import Blueprint, request, jsonify
import re
from app import db
from models.user import User

# Validate email format
def is_valid_email(email):
    pattern = r"^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$"
    return re.match(pattern, email) is not None

# Create a Blueprint
main = Blueprint("main", __name__)

# Home page
@main.route("/")
def home():
    return "Welcome to Python AWS 3-Tier DevOps Project!"

# Health check endpoint
@main.route("/health")
def health():
    return {
        "status": "healthy",
        "application": "Python Flask"
    }, 200

# Create a new user
@main.route("/users", methods=["POST"])
def create_user():
    data = request.get_json()

    # Check if request contains JSON
    if not data:
        return jsonify({"error": "Request body must contain JSON"}), 400

    # Get name and email
    name = data.get("name")
    email = data.get("email")

    # Check required fields
    if not name or not email:
        return jsonify({
            "error": "Name and email are required"
        }), 400

    # Validate email format
    if not is_valid_email(email):
        return jsonify({
            "error": "Invalid email format"
        }), 400

    # Check duplicate email
    existing_user = User.query.filter_by(email=email).first()

    if existing_user:
        return jsonify({
            "error": "Email already exists"
        }), 409

        # Create new user
    new_user = User(name=name, email=email)

    try:
        db.session.add(new_user)
        db.session.commit()

    except SQLAlchemyError:
        db.session.rollback()

        return jsonify({
            "error": "Database error occurred"
        }), 500

    return jsonify({
        "message": "User created successfully",
        "id": new_user.id
    }), 201

    # Get all users
@main.route("/users", methods=["GET"])
def get_users():
    users = User.query.all()

    return jsonify([
        {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
        for user in users
    ]), 200

    # Update an existing user
@main.route("/users/<int:user_id>", methods=["PUT"])
def update_user(user_id):
    user = User.query.get_or_404(user_id)

    data = request.get_json()

    user.name = data["name"]
    user.email = data["email"]

    db.session.commit()

    return jsonify({
        "message": "User updated successfully"
    }), 200

# Delete an existing user
@main.route("/users/<int:user_id>", methods=["DELETE"])
def delete_user(user_id):
    user = User.query.get_or_404(user_id)

    db.session.delete(user)
    db.session.commit()

    return jsonify({
        "message": "User deleted successfully"
    }), 200